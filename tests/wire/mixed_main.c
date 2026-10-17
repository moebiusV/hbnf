/* A text rule that names a bit rule: both read from one parser. */
#include <stdio.h>
#include <string.h>
#include "mixed.c"

static void show(const char *what, const char *text) {
    msg_t out;
    char err[512];
    size_t line = 0, col = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("%s: len=%u body=%.*s\n", what, (unsigned)out.frame.len,
               (int)out.frame.body.len, out.frame.body.ptr);
    else
        printf("%s: error\n%s\n", what, err);
}

int main(void) {
    show("hello", "PKT:\x05hello;");
    show("one", "PKT:\x01z;");
    show("short", "PKT:\x09hello;");
    show("no semicolon", "PKT:\x05hello");
    show("no tag", "\x05hello;");
    return 0;
}
