/* Reads a parenthesised list of words on stdin, and prints the list as `layout rb` holds it: one word a
   line, in the order of the tree.  Built after the generated parser (cat parser.c rb-main.c). */
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    static char buf[1 << 20];
    size_t n = fread(buf, 1, sizeof buf - 1, stdin), line, col;
    char err[256];
    top_t t;
    top_1_t *e;
    buf[n] = 0;
    if (!parse_text(buf, &t, err, sizeof err, &line, &col)) { printf("refused: %s\n", err); return 1; }
    RB_FOREACH(e, top_1_list, &t.top_1) printf("%.*s\n", (int)hbnf_sn(e->word), hbnf_sp(e->word));
    return 0;
}
