/* adler32.h -- Adler-32, as zlib's adler32.
 *
 *     hbnf_adler32 (data, n)
 *
 * One header of static functions, no dependencies beyond the C library's
 * <stddef.h> and <stdint.h>: include it from a grammar's preamble,
 *
 *     { #include "adler32.h" }
 *
 * and call it from an `%action{ }` or `%emit{ }`.  hbnf never reads it.
 * ISC licence, as the rest of hbnf.
 */
#ifndef HBNF_ADLER32_H
#define HBNF_ADLER32_H

#include <stddef.h>
#include <stdint.h>

#if defined(__GNUC__)
#define HBNF_UNUSED __attribute__ ((unused))
#else
#define HBNF_UNUSED
#endif

static uint32_t hbnf_adler32 (const void *data, size_t n) HBNF_UNUSED;
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

#endif /* HBNF_ADLER32_H */
