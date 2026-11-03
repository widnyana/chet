#include <metal_stdlib>
using namespace metal;

constant int PHOTO_SIDE = 256;
constant int PHOTO_SMALL = 32;

static inline int photo_gray(device const uchar *px, int x, int y) {
    device const uchar *p = px + (y * PHOTO_SIDE + x) * 4;
    return (77 * int(p[0]) + 150 * int(p[1]) + 29 * int(p[2])) >> 8;
}

// One thread per image. Must match PerceptualHash.cpu exactly.
kernel void photo_features(device const uchar *rgba [[buffer(0)]],
                           device const int *cosTable [[buffer(1)]],
                           device ulong *hashes [[buffer(2)]],
                           device long *lap [[buffer(3)]],
                           uint img [[thread_position_in_grid]]) {
    device const uchar *px = rgba + ulong(img) * PHOTO_SIDE * PHOTO_SIDE * 4;

    int small[PHOTO_SMALL * PHOTO_SMALL];
    for (int by = 0; by < PHOTO_SMALL; by++) {
        for (int bx = 0; bx < PHOTO_SMALL; bx++) {
            int sum = 0;
            for (int y = 0; y < 8; y++) {
                for (int x = 0; x < 8; x++) {
                    sum += photo_gray(px, bx * 8 + x, by * 8 + y);
                }
            }
            small[by * PHOTO_SMALL + bx] = sum / 64;
        }
    }

    int rows[PHOTO_SMALL * 8];
    for (int y = 0; y < PHOTO_SMALL; y++) {
        for (int u = 0; u < 8; u++) {
            int acc = 0;
            for (int x = 0; x < PHOTO_SMALL; x++) {
                acc += small[y * PHOTO_SMALL + x] * cosTable[u * PHOTO_SMALL + x];
            }
            rows[y * 8 + u] = acc;
        }
    }

    long coef[64];
    for (int v = 0; v < 8; v++) {
        for (int u = 0; u < 8; u++) {
            long acc = 0;
            for (int y = 0; y < PHOTO_SMALL; y++) {
                acc += long(rows[y * 8 + u]) * long(cosTable[v * PHOTO_SMALL + y]);
            }
            coef[v * 8 + u] = acc;
        }
    }

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
    long median2 = sorted[31] + sorted[32];
    ulong hash = 0;
    for (int i = 0; i < 64; i++) {
        if (2 * coef[i] > median2) {
            hash |= ulong(1) << ulong(i);
        }
    }
    hashes[img] = hash;

    long sum = 0;
    long squares = 0;
    for (int y = 1; y < PHOTO_SIDE - 1; y++) {
        for (int x = 1; x < PHOTO_SIDE - 1; x++) {
            long l = 4 * photo_gray(px, x, y) - photo_gray(px, x, y - 1) - photo_gray(px, x, y + 1)
                - photo_gray(px, x - 1, y) - photo_gray(px, x + 1, y);
            sum += l;
            squares += l * l;
        }
    }
    lap[img * 2] = sum;
    lap[img * 2 + 1] = squares;
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
