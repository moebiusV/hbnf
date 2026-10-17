/* A bit rule that holds a text token. */
#include <stdio.h>
#include <string.h>
#include "mixed2.c"

static void show(const char *what, const char *text) {
    doc_t out;
    char err[512];
    size_t line = 0, col = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("%s: kind=%u label=%s\n", what, (unsigned)out.record.kind,
               out.record.label);
    else
        printf("%s: error\n%s\n", what, err);
}

int main(void) {
    show("abc", "REC:\x07" "abc");
    show("a letter as the kind", "REC:abc");
    show("no label", "REC:\x07");
    show("digits", "REC:\x07" "123");
    return 0;
}
