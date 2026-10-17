/* bip39.h -- BIP-39's own arithmetic, for the actions and emitters of a mnemonic
 * grammar (tests/wire/mnemonic.hbnf).  The hash it needs is the general one in
 * lib/hbnf_sum.h; this file is what only BIP-39 knows.
 *
 *     { #include "bip39.h" }          (compile with -Ilib -Icorpus/bip39)
 *
 * ISC licence, as the rest of hbnf.
 */
#ifndef BIP39_H
#define BIP39_H

#include <stddef.h>
#include <stdint.h>
#include "hbnf_sum.h"

/* The checksum of an entropy of n octets (16 to 32, a multiple of 4): the first
 * n/4 bits of its SHA-256, as a number.  A mnemonic is the entropy followed by
 * these bits, cut into 11-bit words. */
static unsigned bip39_checksum (const uint8_t *entropy, size_t n) HBNF_SUM_UNUSED;
static unsigned bip39_checksum (const uint8_t *entropy, size_t n) {
    uint8_t h[32];
    hbnf_sha256 (entropy, n, h);
    return (unsigned)(h[0] >> (8 - n / 4));
}

/* The number of words for n octets of entropy. */
static unsigned bip39_words (size_t n) HBNF_SUM_UNUSED;
static unsigned bip39_words (size_t n) {
    return (unsigned)((n * 8 + n / 4) / 11);
}

#endif /* BIP39_H */
