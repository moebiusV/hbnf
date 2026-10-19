/* A mixed grammar written back: read the text, write the tree. */
#include <stdio.h>
#include <string.h>
#include "mixed.c"

int main(void) {
    const char *in[] = { "PKT:\x05hello;", "PKT:\x01z;" };
    for (int i = 0; i < 2; i++) {
        msg_t out;
        char err[256], buf[64];
        size_t line, col, n;
        int len = i ? 7 : 11;
        if (!parse_text(in[i], &out, err, sizeof err, &line, &col)) {
            printf("read %d: %s\n", i, err);
            continue;
        }
        n = write_msg(&out, buf, sizeof buf);
        printf("write %d: %s %zu bytes, same as read: %s\n", i,
               n == (size_t)-1 ? hbnf_write_error : "ok", n,
               n == (size_t)len && !memcmp(buf, in[i], n) ? "yes" : "no");
    }
    return 0;
}
