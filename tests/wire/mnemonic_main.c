/* BIP-39 mnemonics: the entropy, and the phrase and checksum value computed
   from it by a script that shares nothing with hbnf (SHA-256 and the English
   list).  The published test vectors are among them (12, 18 and 24 words).
   Every length but 12 and 24 words comes back with the action's warning. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "mnemonic.c"

struct vec { const char *phrase; unsigned n; const uint8_t *entropy; unsigned cs; };
static const uint8_t e0[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const uint8_t e1[] = {0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f};
static const uint8_t e2[] = {0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80};
static const uint8_t e3[] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
static const uint8_t e4[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const uint8_t e5[] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
static const uint8_t e6[] = {0x0c,0x1e,0x24,0xe5,0x91,0x77,0x79,0xd2,0x97,0xe1,0x4d,0x45,0xf1,0x4e,0x1a,0x1a};
static const uint8_t e7[] = {0x9e,0x88,0x5d,0x95,0x2a,0xd3,0x62,0xca,0xeb,0x4e,0xfe,0x34,0xa8,0xe9,0x1b,0xd2};
static const uint8_t e8[] = {0x06,0x6d,0xca,0x1a,0x2b,0xb7,0xe8,0xa1,0xdb,0x28,0x32,0x14,0x8c,0xe9,0x93,0x3e,0xea,0x0f,0x3a,0xc9,0x54,0x8d,0x79,0x31,0x12,0xd9,0xa9,0x5c,0x94,0x07,0xef,0xad};
static const uint8_t e9[] = {0xf5,0x85,0xc1,0x1a,0xec,0x52,0x0d,0xb5,0x7d,0xd3,0x53,0xc6,0x95,0x54,0xb2,0x1a,0x89,0xb2,0x0f,0xb0,0x65,0x09,0x66,0xfa,0x0a,0x9d,0x6f,0x74,0xfd,0x98,0x9d,0x8f};
static const uint8_t e10[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const uint8_t e11[] = {0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f};
static const uint8_t e12[] = {0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80};
static const uint8_t e13[] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
static const uint8_t e14[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const uint8_t e15[] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
static const uint8_t e16[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00};
static const uint8_t e17[] = {0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff};
static const struct vec vecs[] = {
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", 16, e0, 3 },
    { "legal winner thank year wave sausage worth useful legal winner thank yellow", 16, e1, 8 },
    { "letter advice cage absurd amount doctor acoustic avoid letter advice cage above", 16, e2, 4 },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", 16, e3, 5 },
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", 32, e4, 102 },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", 32, e5, 175 },
    { "army van defense carry jealous true garbage claim echo media make crunch", 16, e6, 7 },
    { "ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", 16, e7, 1 },
    { "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform", 32, e8, 162 },
    { "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold", 32, e9, 105 },
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent", 24, e10, 39 },
    { "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will", 24, e11, 25 },
    { "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always", 24, e12, 60 },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when", 24, e13, 17 },
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon address", 20, e14, 27 },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrist", 20, e15, 19 },
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon admit", 28, e16, 29 },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo veteran", 28, e17, 25 },
};

int main(void) {
    int bad = 0;
    for (size_t i = 0; i < sizeof vecs / sizeof vecs[0]; i++) {
        bnf_mnemonic_t out;  char err[256];  size_t at;
        char back[400];  size_t m = 0;
        unsigned words = (vecs[i].n * 8 + vecs[i].n * 8 / 32) / 11;
        unsigned want_warn = vecs[i].n != 16 && vecs[i].n != 32;
        if (!parse_text(vecs[i].phrase, strlen(vecs[i].phrase), &out, err, sizeof err, &at)) {
            printf("FAIL %u words: %s\n", words, err);  bad++;  continue;
        }
        if (out.entropy.len != vecs[i].n || memcmp(out.entropy.ptr, vecs[i].entropy, vecs[i].n)
            || (unsigned)out.checksum != vecs[i].cs) {
            printf("FAIL %u words: entropy or checksum differs\n", words);  bad++;
        } else if (out.nwarnings != want_warn) {
            printf("FAIL %u words: %u warning(s)\n", words, out.nwarnings);  bad++;
        } else if (!emit_text(&out, back, sizeof back, &m, err, sizeof err)) {
            printf("FAIL %u words: emit: %s\n", words, err);  bad++;
        } else if (m != strlen(vecs[i].phrase) || memcmp(back, vecs[i].phrase, m)) {
            printf("FAIL %u words: written back as %s\n", words, back);  bad++;
        } else
            printf("PASS %u words, entropy %u octets, checksum %u%s%s, written back\n",
                   words, vecs[i].n, vecs[i].cs, out.nwarnings ? ", warning: " : "",
                   out.nwarnings ? out.warnings[0] : "");
        free_arena();
    }
    {   bnf_mnemonic_t out;  char err[256];  size_t at;
        static const char *no[] = {
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandonn",
            "abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about ",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon",
            "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo",
            "" };
        static const char *why[] = { "11 words", "a misspelt word", "two blanks", "a trailing blank",
                                     "a wrong checksum (all abandon)", "a wrong checksum (all zoo)", "nothing" };
        for (size_t i = 0; i < sizeof no / sizeof no[0]; i++) {
            if (parse_text(no[i], strlen(no[i]), &out, err, sizeof err, &at))
                { printf("FAIL accepted: %s\n", why[i]);  bad++; }
            else printf("PASS refused: %s (%s)\n", why[i], err);
            free_arena();
        }
    }
    {   /* writing: only the entropy is set, and %emit works out the checksum */
        for (size_t i = 0; i < sizeof vecs / sizeof vecs[0]; i++) {
            bnf_mnemonic_t t;  char back[400], err[256];  size_t m = 0;
            memset(&t, 0, sizeof t);
            t.entropy.ptr = vecs[i].entropy;
            t.entropy.len = vecs[i].n;
            t.checksum = 0x55;      /* wrong on purpose: it is computed */
            if (!emit_text(&t, back, sizeof back, &m, err, sizeof err))
                { printf("FAIL generate %zu: %s\n", i, err);  bad++; }
            else if (m != strlen(vecs[i].phrase) || memcmp(back, vecs[i].phrase, m))
                { printf("FAIL generate %zu: %s\n", i, back);  bad++; }
            else printf("PASS generated %u words from %u octets of entropy\n",
                        (vecs[i].n * 8 + vecs[i].n * 8 / 32) / 11, vecs[i].n);
        }
    }
    return bad != 0;
}
