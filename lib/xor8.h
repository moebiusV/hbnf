/* xor8.h -- the exclusive-or of the octets.
 *
 *     hbnf_xor8 (data, n)
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "xor8.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_XOR8_H
#define HBNF_XOR8_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

static uint8_t hbnf_xor8 (const void *data, size_t n) HBNF_UNUSED;
static uint8_t hbnf_xor8 (const void *data, size_t n) {
    const uint8_t *p = (const uint8_t *)data;
    uint8_t x = 0;
    size_t i;
    for (i = 0; i < n; i++)
        x ^= p[i];
    return x;
}

#endif /* HBNF_XOR8_H */
