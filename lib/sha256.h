/* sha256.h -- SHA-256 (FIPS 180-4).
 *
 *     hbnf_sha256 (data, n, out32)
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "sha256.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_SHA256_H
#define HBNF_SHA256_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

#define HBNF_ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void hbnf_sha256_block (uint32_t h[8], const uint8_t *b) HBNF_UNUSED;
static void hbnf_sha256_block (uint32_t h[8], const uint8_t *b) {
    static const uint32_t K[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2 };
    uint32_t w[64], a, bb, c, d, e, f, g, hh;
    int i;
    for (i = 0; i < 16; i++)
        w[i] = (uint32_t)b[4 * i] << 24 | (uint32_t)b[4 * i + 1] << 16
             | (uint32_t)b[4 * i + 2] << 8 | (uint32_t)b[4 * i + 3];
    for (i = 16; i < 64; i++) {
        uint32_t s0 = HBNF_ROR32 (w[i - 15], 7) ^ HBNF_ROR32 (w[i - 15], 18)
                      ^ (w[i - 15] >> 3);
        uint32_t s1 = HBNF_ROR32 (w[i - 2], 17) ^ HBNF_ROR32 (w[i - 2], 19)
                      ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = h[0]; bb = h[1]; c = h[2]; d = h[3];
    e = h[4]; f = h[5]; g = h[6]; hh = h[7];
    for (i = 0; i < 64; i++) {
        uint32_t S1 = HBNF_ROR32 (e, 6) ^ HBNF_ROR32 (e, 11) ^ HBNF_ROR32 (e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = hh + S1 + ch + K[i] + w[i];
        uint32_t S0 = HBNF_ROR32 (a, 2) ^ HBNF_ROR32 (a, 13) ^ HBNF_ROR32 (a, 22);
        uint32_t mj = (a & bb) ^ (a & c) ^ (bb & c);
        uint32_t t2 = S0 + mj;
        hh = g; g = f; f = e; e = d + t1;
        d = c; c = bb; bb = a; a = t1 + t2;
    }
    h[0] += a; h[1] += bb; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

static void hbnf_sha256 (const void *data, size_t len, uint8_t out[32]) HBNF_UNUSED;
static void hbnf_sha256 (const void *data, size_t len, uint8_t out[32]) {
    const uint8_t *msg = (const uint8_t *)data;
    uint32_t h[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    uint8_t blk[128];
    size_t i, full = len / 64, rest = len % 64, total;
    uint64_t bits = (uint64_t)len * 8;
    for (i = 0; i < full; i++)
        hbnf_sha256_block (h, msg + 64 * i);
    for (i = 0; i < sizeof blk; i++)
        blk[i] = 0;
    for (i = 0; i < rest; i++)
        blk[i] = msg[64 * full + i];
    blk[rest] = 0x80;
    total = rest + 1 + 8 > 64 ? 128 : 64;
    for (i = 0; i < 8; i++)
        blk[total - 1 - i] = (uint8_t)(bits >> (8 * i));
    hbnf_sha256_block (h, blk);
    if (total == 128)
        hbnf_sha256_block (h, blk + 64);
    for (i = 0; i < 8; i++) {
        out[4 * i]     = (uint8_t)(h[i] >> 24);
        out[4 * i + 1] = (uint8_t)(h[i] >> 16);
        out[4 * i + 2] = (uint8_t)(h[i] >> 8);
        out[4 * i + 3] = (uint8_t)h[i];
    }
}

#endif /* HBNF_SHA256_H */
