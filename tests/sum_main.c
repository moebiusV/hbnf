/* the headers in lib/ against published values. */
#include <stdio.h>
#include <string.h>
#include "sha256.h"
#include "crc.h"
#include "adler32.h"
#include "inet_checksum.h"
#include "xor8.h"
#include "bech32.h"

static int bad;

static void hex(const uint8_t *p, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) sprintf(out + 2 * i, "%02x", p[i]);
}

static void sha(const char *what, const char *msg, const char *want) {
    uint8_t d[32]; char h[65];
    hbnf_sha256(msg, strlen(msg), d); hex(d, 32, h);
    if (strcmp(h, want)) { printf("FAIL sha256 %s: %s\n", what, h); bad++; }
    else printf("PASS sha256 %s\n", what);
}

static void num(const char *what, unsigned long got, unsigned long want) {
    if (got != want) { printf("FAIL %s: %lx, wanted %lx\n", what, got, want); bad++; }
    else printf("PASS %s\n", what);
}

int main(void) {
    sha("empty", "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    sha("abc", "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    sha("two blocks", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    num("crc32 \"123456789\"", hbnf_crc32("123456789", 9), 0xcbf43926ul);
    num("crc16_ccitt \"123456789\"", hbnf_crc16_ccitt("123456789", 9), 0x29b1ul);
    num("adler32 \"Wikipedia\"", hbnf_adler32("Wikipedia", 9), 0x11e60398ul);
    {   static const uint8_t d[] = { 0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7 };
        num("inet_checksum (RFC 1071)", hbnf_inet_checksum(d, sizeof d), 0x220dul);
        num("inet_checksum, odd length (padded with a zero octet)", hbnf_inet_checksum(d, 7), 0x2304ul);
    }
    num("xor8", hbnf_xor8("abc", 3), 'a' ^ 'b' ^ 'c');
    {   /* BIP-173: the data part of each valid address, as 5-bit values */
        static const char cs[] = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
        static const struct { const char *hrp, *data; int kind; } v[] = {
            { "bc", "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", 1 },
            { "tb", "qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", 1 },
            { "bc", "p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", 2 },
            { "bc", "sw50qgdz25j", 2 },
            { "bc", "zw508d6qejxtdg4y5r3zarvaryvaxxpcs", 2 },
            { "bc", "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", 0 },   /* last symbol changed */
        };
        for (size_t i = 0; i < sizeof v / sizeof v[0]; i++) {
            uint8_t x[100]; size_t n = strlen(v[i].data);
            for (size_t k = 0; k < n; k++) x[k] = (uint8_t)(strchr(cs, v[i].data[k]) - cs);
            int got = hbnf_bech32_verify(v[i].hrp, x, n);
            if (got != v[i].kind) { printf("FAIL bech32 %s1%s: %d\n", v[i].hrp, v[i].data, got); bad++; }
            else printf("PASS bech32 %s1%.12s...: %s\n", v[i].hrp, v[i].data,
                        got == 1 ? "bech32" : got == 2 ? "bech32m" : "not valid");
        }
    }
    return bad != 0;
}
