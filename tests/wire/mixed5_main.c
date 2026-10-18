/* %action on a bit rule inside a text grammar: failure and warnings. */
#include <stdio.h>
#include "mixed5.c"

static void show(const char *what, const char *text) {
    doc_t out;
    char err[512];
    size_t line = 0, col = 0;
    unsigned i;
    bnf_act_nwarn = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("%s: kind=%u len=%u\n", what, (unsigned)out.rec.kind,
               (unsigned)out.rec.len);
    else
        printf("%s: error\n%s\n", what, err);
    for (i = 0; i < hbnf_warnings(); i++)
        printf("  warning: %s\n", hbnf_warning(i));
}

int main(void) {
    show("plain", "REC:\x07\x03;");
    show("long", "REC:\x07\x20;");
    show("reserved", "REC:\xff\x01;");
    return 0;
}
