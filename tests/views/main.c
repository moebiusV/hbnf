/* hbnf_sp / hbnf_sn: a token is a slice of the input; a quoted string with an escape, and one
   of 65535 bytes or more, are copies. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.c"

static int fails;
static void check(const char *what, hbnf_str v, const char *want, size_t n, int borrowed, const char *text) {
    int is_in_text = hbnf_sp(v) >= text && hbnf_sp(v) <= text + strlen(text);
    if (hbnf_sn(v) != n || memcmp(hbnf_sp(v), want, n) != 0) { printf("FAIL %s: wrong text\n", what); fails++; }
    else if (borrowed != is_in_text) { printf("FAIL %s: %s the input\n", what, borrowed ? "not in" : "in"); fails++; }
}

int main(void) {
    char err[256]; size_t line, col;
    bnf_doc_t d;
    const char *t1 = "key \"plain\"";
    const char *t2 = "key \"a\\\"b\"";
    size_t big = 70000;
    char *t3 = malloc(big + 32);

    if (!parse_text(t1, &d, err, sizeof err, &line, &col)) { printf("FAIL parse 1: %s\n", err); return 1; }
    check("word", d.word, "key", 3, 1, t1);
    check("plain str", d.str, "plain", 5, 1, t1);

    if (!parse_text(t2, &d, err, sizeof err, &line, &col)) { printf("FAIL parse 2: %s\n", err); return 1; }
    check("escaped str", d.str, "a\"b", 3, 0, t2);

    strcpy(t3, "key \""); memset(t3 + 5, 'x', big); strcpy(t3 + 5 + big, "\"");
    if (!parse_text(t3, &d, err, sizeof err, &line, &col)) { printf("FAIL parse 3: %s\n", err); return 1; }
    if (hbnf_sn(d.str) != big) { printf("FAIL long str: length %zu\n", hbnf_sn(d.str)); fails++; }
    free(t3);
    if (!fails) puts("views: OK");
    return fails != 0;
}
