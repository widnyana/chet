#include <metal_stdlib>
using namespace metal;

constant int PHOTO_SIDE = 256;
constant int PHOTO_SMALL = 32;

static inline int photo_gray(device const uchar *px, int x, int y) {
    device const uchar *p = px + (y * PHOTO_SIDE + x) * 4;
    return (77 * int(p[0]) + 150 * int(p[1]) + 29 * int(p[2])) >> 8;
}

// One threadgroup per image. Threads cooperate on the grayscale cells, the row and column
// transforms, and the laplacian sum. Every reduction is an integer sum, which is order
// independent, so the result matches PerceptualHash.cpu exactly.
constant int PHOTO_THREADS = 256;

kernel void photo_features(device const uchar *rgba [[buffer(0)]],
                           device const int *cosTable [[buffer(1)]],
                           device ulong *hashes [[buffer(2)]],
                           device long *lap [[buffer(3)]],
                           uint imageID [[threadgroup_position_in_grid]],
                           uint tid [[thread_position_in_threadgroup]]) {
    threadgroup int small[PHOTO_SMALL * PHOTO_SMALL];
    threadgroup int rows[PHOTO_SMALL * 8];
    threadgroup long coef[64];
    threadgroup long median2;
    threadgroup long reduceSum[PHOTO_THREADS];
    threadgroup long reduceSquares[PHOTO_THREADS];

    device const uchar *px = rgba + ulong(imageID) * PHOTO_SIDE * PHOTO_SIDE * 4;

    // 1024 cells, 4 per thread.
    for (int c = int(tid); c < PHOTO_SMALL * PHOTO_SMALL; c += PHOTO_THREADS) {
        int bx = c % PHOTO_SMALL;
        int by = c / PHOTO_SMALL;
        int sum = 0;
        for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
                sum += photo_gray(px, bx * 8 + x, by * 8 + y);
            }
        }
        small[c] = sum / 64;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // rows[y * 8 + u]
    if (tid < uint(PHOTO_SMALL * 8)) {
        int y = int(tid) / 8;
        int u = int(tid) % 8;
        int acc = 0;
        for (int x = 0; x < PHOTO_SMALL; x++) {
            acc += small[y * PHOTO_SMALL + x] * cosTable[u * PHOTO_SMALL + x];
        }
        rows[tid] = acc;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // coef[v * 8 + u]
    if (tid < 64) {
        int v = int(tid) / 8;
        int u = int(tid) % 8;
        long acc = 0;
        for (int y = 0; y < PHOTO_SMALL; y++) {
            acc += long(rows[y * 8 + u]) * long(cosTable[v * PHOTO_SMALL + y]);
        }
        coef[tid] = acc;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Median of the 64 coefficients, then the 64 hash bits. Same insertion sort as the CPU.
    if (tid == 0) {
        long sorted[64];
        for (int i = 0; i < 64; i++) {
            sorted[i] = coef[i];
        }
        for (int i = 1; i < 64; i++) {
            long key = sorted[i];
            int j = i - 1;
            while (j >= 0 && sorted[j] > key) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = key;
        }
        median2 = sorted[31] + sorted[32];
        ulong hash = 0;
        for (int i = 0; i < 64; i++) {
            if (2 * coef[i] > median2) {
                hash |= ulong(1) << ulong(i);
            }
        }
        hashes[imageID] = hash;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Laplacian over the 254 x 254 interior, then an exact integer reduction.
    long sum = 0;
    long squares = 0;
    for (int p = int(tid); p < (PHOTO_SIDE - 2) * (PHOTO_SIDE - 2); p += PHOTO_THREADS) {
        int y = 1 + p / (PHOTO_SIDE - 2);
        int x = 1 + p % (PHOTO_SIDE - 2);
        long l = 4 * photo_gray(px, x, y) - photo_gray(px, x, y - 1) - photo_gray(px, x, y + 1)
            - photo_gray(px, x - 1, y) - photo_gray(px, x + 1, y);
        sum += l;
        squares += l * l;
    }
    reduceSum[tid] = sum;
    reduceSquares[tid] = squares;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = PHOTO_THREADS / 2; stride > 0; stride >>= 1) {
        if (tid < stride) {
            reduceSum[tid] += reduceSum[tid + stride];
            reduceSquares[tid] += reduceSquares[tid + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        lap[imageID * 2] = reduceSum[0];
        lap[imageID * 2 + 1] = reduceSquares[0];
    }
}

// One thread per (i, j) inside one tile starting at origin (x = column j, y = row i).
// Appends pairs i < j whose hashes differ in at most maxDistance bits.
kernel void hamming_pairs(device const ulong *hashes [[buffer(0)]],
                          constant uint &count [[buffer(1)]],
                          constant uint &maxDistance [[buffer(2)]],
                          device atomic_uint *found [[buffer(3)]],
                          device uint2 *pairs [[buffer(4)]],
                          constant uint &capacity [[buffer(5)]],
                          constant uint2 &origin [[buffer(6)]],
                          uint2 pos [[thread_position_in_grid]]) {
    uint i = origin.y + pos.y;
    uint j = origin.x + pos.x;
    if (i >= count || j >= count || j <= i) {
        return;
    }
    if (popcount(hashes[i] ^ hashes[j]) > ulong(maxDistance)) {
        return;
    }
    uint slot = atomic_fetch_add_explicit(found, 1, memory_order_relaxed);
    if (slot < capacity) {
        pairs[slot] = uint2(i, j);
    }
}
