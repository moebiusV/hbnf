/* inet_checksum.h -- the Internet checksum (RFC 1071).
 *
 *     hbnf_inet_checksum (data, n)  the complement of the 16-bit one's-complement
 *                                   sum, as IPv4, ICMP, TCP and UDP use
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "inet_checksum.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_INET_CHECKSUM_H
#define HBNF_INET_CHECKSUM_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

static uint16_t hbnf_inet_checksum (const void *data, size_t n) HBNF_UNUSED;
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

#endif /* HBNF_INET_CHECKSUM_H */
