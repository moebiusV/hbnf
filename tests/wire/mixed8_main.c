/* Alternatives in a mixed grammar, written back: read the text, write the tree. */
#include <stdio.h>
#include <string.h>
#include "mixed8.c"

int main(void) {
    const char *in[] = { "A:\x07\x03;", "B:abc;", "L:x\x01\x02yfoo,x\x03\x04;" };
    for (int i = 0; i < 3; i++) {
        doc_t out;
        char err[256], buf[64];
        size_t line, col, n;
        if (!parse_text(in[i], &out, err, sizeof err, &line, &col)) {
            printf("read %d: %s\n", i, err);
            continue;
        }
        n = write_doc(&out, buf, sizeof buf);
        printf("write %d: %s %zu bytes, same as read: %s\n", i,
               n == (size_t)-1 ? hbnf_write_error : "ok", n,
               n == strlen(in[i]) && !memcmp(buf, in[i], n) ? "yes" : "no");
    }
    return 0;
}
