/* bip39.h -- BIP-39's own arithmetic, for the actions and emitters of a mnemonic
 * grammar (tests/wire/mnemonic.hbnf).  The hash is the system's: OpenSSL's
 * SHA256, so the program links -lcrypto.
 *
 *     { #include "bip39.h" }          (compile with -Icorpus/bip39, link -lcrypto)
 *
 * ISC licence, as the rest of hbnf.
 */
#ifndef BIP39_H
#define BIP39_H

#include <stddef.h>
#include <stdint.h>
#include <openssl/sha.h>

/* The checksum of an entropy of n octets (16 to 32, a multiple of 4): the first
 * n/4 bits of its SHA-256, as a number.  A mnemonic is the entropy followed by
 * these bits, cut into 11-bit words. */
static unsigned bip39_checksum (const uint8_t *entropy, size_t n) {
    unsigned char h[SHA256_DIGEST_LENGTH];
    SHA256 (entropy, n, h);
    return (unsigned)(h[0] >> (8 - n / 4));
}

#endif /* BIP39_H */
