/* hbnf_sum.h -- checksums and hashes for the actions and emitters of a wire
 * grammar.  One header, no dependencies beyond <stdint.h> and <stddef.h>, every
 * function static: include it from a grammar's preamble,
 *
 *     { #include "hbnf_sum.h" }
 *
 * and call it from `%action{ }` (to check a checksum on reading) or `%emit{ }`
 * (to compute one when writing).  The generator never reads or rewrites it.
 *
 *     hbnf_sha256 (data, n, out32)           SHA-256 (FIPS 180-4)
 *     hbnf_crc32 (data, n)                   CRC-32/IEEE 802.3, as zlib's crc32
 *     hbnf_crc16_ccitt (data, n)             CRC-16/CCITT-FALSE: poly 0x1021,
 *                                            start 0xFFFF, no reflection
 *     hbnf_adler32 (data, n)                 Adler-32, as zlib's
 *     hbnf_inet_checksum (data, n)           RFC 1071: the complement of the
 *                                            16-bit one's-complement sum
 *     hbnf_xor8 (data, n)                    the exclusive-or of the octets
 *     hbnf_bech32_polymod (v, n, chk)        BIP-173's BCH code over 5-bit
 *     hbnf_bech32_hrp_polymod (hrp, chk)     values; see hbnf_bech32_verify
 *     hbnf_bech32_verify (hrp, v, n)         1: bech32, 2: bech32m, 0: neither
 *
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_SUM_H
#define HBNF_SUM_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_SUM_UNUSED __attribute__ ((unused))
#else
#define HBNF_SUM_UNUSED
#endif

/* ---- SHA-256 ---- */

#define HBNF_ROR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void hbnf_sha256_block (uint32_t h[8], const uint8_t *b) HBNF_SUM_UNUSED;
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

static void hbnf_sha256 (const void *data, size_t len, uint8_t out[32]) HBNF_SUM_UNUSED;
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

/* ---- the small ones ---- */

static uint32_t hbnf_crc32 (const void *data, size_t n) HBNF_SUM_UNUSED;
static uint32_t hbnf_crc32 (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint32_t c = 0xFFFFFFFFu;
    size_t i;
    int k;
    for (i = 0; i < n; i++) {
        c ^= p[i];
        for (k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
    }
    return c ^ 0xFFFFFFFFu;
}

static uint16_t hbnf_crc16_ccitt (const void *data, size_t n) HBNF_SUM_UNUSED;
static uint16_t hbnf_crc16_ccitt (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint16_t c = 0xFFFF;
    size_t i;
    int k;
    for (i = 0; i < n; i++) {
        c = (uint16_t)(c ^ (uint16_t)(p[i] << 8));
        for (k = 0; k < 8; k++)
            c = (uint16_t)((c & 0x8000) ? (c << 1) ^ 0x1021 : c << 1);
    }
    return c;
}

static uint32_t hbnf_adler32 (const void *data, size_t n) HBNF_SUM_UNUSED;
static uint32_t hbnf_adler32 (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint32_t a = 1, b = 0;
    size_t i;
    for (i = 0; i < n; i++) {
        a = (a + p[i]) % 65521u;
        b = (b + a) % 65521u;
    }
    return (b << 16) | a;
}

static uint16_t hbnf_inet_checksum (const void *data, size_t n) HBNF_SUM_UNUSED;
static uint16_t hbnf_inet_checksum (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint32_t s = 0;
    size_t i;
    for (i = 0; i + 1 < n; i += 2)
        s += (uint32_t)(p[i] << 8 | p[i + 1]);
    if (n & 1)
        s += (uint32_t)(p[n - 1] << 8);
    while (s >> 16)
        s = (s & 0xFFFF) + (s >> 16);
    return (uint16_t)~s;
}

static uint8_t hbnf_xor8 (const void *data, size_t n) HBNF_SUM_UNUSED;
static uint8_t hbnf_xor8 (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint8_t x = 0;
    size_t i;
    for (i = 0; i < n; i++)
        x ^= p[i];
    return x;
}

/* ---- bech32 (BIP-173) and bech32m (BIP-350) ----
 * The values are 5-bit.  A string is valid when the polymod of the human-readable
 * part, expanded, followed by the data part, checksum included, is 1 (bech32) or
 * 0x2bc830a3 (bech32m). */

static uint32_t hbnf_bech32_polymod (const uint8_t *v, size_t n, uint32_t chk) HBNF_SUM_UNUSED;
static uint32_t hbnf_bech32_polymod (const uint8_t *v, size_t n, uint32_t chk) {
    static const uint32_t G[5] = { 0x3b6a57b2, 0x26508e6d, 0x1ea119fa,
                                   0x3d4233dd, 0x2a1462b3 };
    size_t i;
    int k;
    for (i = 0; i < n; i++) {
        uint32_t top = chk >> 25;
        chk = (chk & 0x1ffffff) << 5 ^ v[i];
        for (k = 0; k < 5; k++)
            if ((top >> k) & 1)
                chk ^= G[k];
    }
    return chk;
}

/* The start of the polymod for a human-readable part (a string): its high bits,
 * a zero, its low bits.  Start from 1. */
static uint32_t hbnf_bech32_hrp_polymod (const char *hrp, uint32_t chk) HBNF_SUM_UNUSED;
static uint32_t hbnf_bech32_hrp_polymod (const char *hrp, uint32_t chk) {
    uint8_t b;
    const char *s;
    for (s = hrp; *s; s++) {
        b = (uint8_t)((uint8_t)*s >> 5);
        chk = hbnf_bech32_polymod (&b, 1, chk);
    }
    b = 0;
    chk = hbnf_bech32_polymod (&b, 1, chk);
    for (s = hrp; *s; s++) {
        b = (uint8_t)((uint8_t)*s & 31);
        chk = hbnf_bech32_polymod (&b, 1, chk);
    }
    return chk;
}

/* 1 if hrp and the n 5-bit values (checksum last) form a bech32 string, 2 if a
 * bech32m string, 0 if neither. */
static int hbnf_bech32_verify (const char *hrp, const uint8_t *v, size_t n) HBNF_SUM_UNUSED;
static int hbnf_bech32_verify (const char *hrp, const uint8_t *v, size_t n) {
    uint32_t c = hbnf_bech32_polymod (v, n, hbnf_bech32_hrp_polymod (hrp, 1));
    return c == 1 ? 1 : c == 0x2bc830a3u ? 2 : 0;
}

#endif /* HBNF_SUM_H */
