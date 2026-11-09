#include <metal_stdlib>
using namespace metal;

constant ulong HASH_P1 = 0x9E3779B97F4A7C15ul;
constant ulong HASH_P2 = 0xC2B2AE3D27D4EB4Ful;
constant uint HASH_BLOCK = 65536;

// One thread per 64 KB block of the chunk. Must match GPUHasher.blockHash exactly.
// Bytes past byteCount up to the next 8-byte boundary are zero (the CPU zeroes them).
kernel void block_hash(device const ulong *words [[buffer(0)]],
                       constant uint &byteCount [[buffer(1)]],
                       constant uint &firstBlock [[buffer(2)]],
                       device ulong2 *out [[buffer(3)]],
                       uint i [[thread_position_in_grid]]) {
    uint start = i * HASH_BLOCK;
    if (start >= byteCount) {
        return;
    }
    uint length = min(HASH_BLOCK, byteCount - start);
    uint wordCount = (length + 7) / 8;
    device const ulong *w = words + start / 8;
    ulong index = ulong(firstBlock + i);
    ulong a = HASH_P1 ^ (index * HASH_P2);
    ulong b = HASH_P2 ^ (index * HASH_P1);
    for (uint k = 0; k < wordCount; k++) {
        ulong v = w[k];
        a = (a ^ v) * HASH_P1;
        a ^= a >> 29;
        b = (b + v) * HASH_P2;
        b = (b << 31) | (b >> 33);
    }
    a ^= ulong(length);
    b ^= ulong(length) * HASH_P1;
    out[i] = ulong2(a, b);
}
