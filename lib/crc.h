/* crc.h -- cyclic redundancy checks.
 *
 *     hbnf_crc32 (data, n)        CRC-32/IEEE 802.3, as zlib's crc32
 *     hbnf_crc16_ccitt (data, n)  CRC-16/CCITT-FALSE: poly 0x1021, start 0xFFFF,
 *                                 no reflection
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "crc.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_CRC_H
#define HBNF_CRC_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

static uint32_t hbnf_crc32 (const void *data, size_t n) HBNF_UNUSED;
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


static uint16_t hbnf_crc16_ccitt (const void *data, size_t n) HBNF_UNUSED;
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

#endif /* HBNF_CRC_H */
