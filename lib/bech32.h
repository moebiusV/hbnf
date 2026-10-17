/* bech32.h -- bech32 (BIP-173) and bech32m (BIP-350) checksums.
 *
 *     hbnf_bech32_polymod (v, n, chk)     the BCH code over 5-bit values
 *     hbnf_bech32_hrp_polymod (hrp, chk)  the start of it for a human-readable part
 *     hbnf_bech32_verify (hrp, v, n)      1: bech32, 2: bech32m, 0: neither
 *
 * The values are 5-bit.  A string is valid when the polymod of the expanded
 * human-readable part, then the data part with its checksum, is 1 (bech32) or
 * 0x2bc830a3 (bech32m).
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "bech32.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_BECH32_H
#define HBNF_BECH32_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

static uint32_t hbnf_bech32_polymod (const uint8_t *v, size_t n, uint32_t chk) HBNF_UNUSED;
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
static uint32_t hbnf_bech32_hrp_polymod (const char *hrp, uint32_t chk) HBNF_UNUSED;
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
static int hbnf_bech32_verify (const char *hrp, const uint8_t *v, size_t n) HBNF_UNUSED;
static int hbnf_bech32_verify (const char *hrp, const uint8_t *v, size_t n) {
    uint32_t c = hbnf_bech32_polymod (v, n, hbnf_bech32_hrp_polymod (hrp, 1));
    return c == 1 ? 1 : c == 0x2bc830a3u ? 2 : 0;
}

#endif /* HBNF_BECH32_H */
