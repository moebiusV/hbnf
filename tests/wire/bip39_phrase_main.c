/* The published BIP-39 test vectors for the English list: the phrase, and the
   11-bit index of each of its words.  The indices were worked out from the
   vector's entropy and the first bits of its SHA-256, which is how BIP-39
   makes a phrase, not from the list file; so a word at the wrong index in
   the generated parser fails here.  (Vectors from the BIP's own test data.) */
#include <stdio.h>
#include <string.h>
#include "bip39_phrase.c"

struct vec { const char *phrase; int n; int idx[24]; };
static const struct vec vecs[] = {
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", 12, {0,0,0,0,0,0,0,0,0,0,0,3} },
    { "legal winner thank year wave sausage worth useful legal winner thank yellow", 12, {1019,2015,1790,2039,1983,1533,2031,1919,1019,2015,1790,2040} },
    { "letter advice cage absurd amount doctor acoustic avoid letter advice cage above", 12, {1028,32,257,8,64,514,16,128,1028,32,257,4} },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", 12, {2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2037} },
    { "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", 24, {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,102} },
    { "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", 24, {2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,2047,1967} },
    { "army van defense carry jealous true garbage claim echo media make crunch", 12, {96,1929,459,279,956,1866,764,333,559,1107,1076,423} },
    { "ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", 12, {1268,535,810,685,433,811,1385,1790,421,570,567,1313} },
};

int main(void) {
    int bad = 0;
    for (size_t v = 0; v < sizeof vecs / sizeof vecs[0]; v++) {
        mnemonic_t out;
        char err[256];
        size_t line = 0, col = 0;
        int k = 0, ok = 1;
        if (!parse_text(vecs[v].phrase, &out, err, sizeof err, &line, &col)) {
            printf("FAIL vector %zu: %s\n", v, err);  bad++;  continue;
        }
        if ((int)out.bip39_word != vecs[v].idx[k++]) ok = 0;
        for (mnemonic_1_t *e = out.mnemonic_1.head; e; e = e->_link) {
            if (k >= vecs[v].n || (int)e->bip39_word != vecs[v].idx[k]) ok = 0;
            k++;
        }
        if (k != vecs[v].n) ok = 0;
        printf("%s vector %zu: %d words\n", ok ? "PASS" : "FAIL", v, k);
        if (!ok) bad++;
        free_arena();
    }
    {   /* the same words with the wrong separator, or a wrong word, do not parse */
        mnemonic_t out;  char err[256];  size_t line, col;
        printf("%s\n", parse_text("abandon  abandon", &out, err, sizeof err, &line, &col)
               ? "FAIL two blanks" : "PASS two blanks refused");
        printf("%s\n", parse_text("abandon abandonn", &out, err, sizeof err, &line, &col)
               ? "FAIL misspelt word" : "PASS misspelt word refused");
        printf("%s\n", parse_text("abandon", &out, err, sizeof err, &line, &col)
               ? "FAIL one word is not a phrase" : "PASS one word is not a phrase");
    }
    return bad != 0;
}
