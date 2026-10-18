/* A text element, bit fields and text again, in one rule. */
#include <stdio.h>
#include <string.h>
#include "mixed4.c"

static void show(const char *what, const char *text) {
    req_t out;
    char err[512];
    size_t line = 0, col = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("%s: len=%u payload=%.*s\n", what, (unsigned)out.req_2.len,
               (int)out.req_2.payload.len, out.req_2.payload.ptr);
    else
        printf("%s: error\n%s\n", what, err);
}

int main(void) {
    show("hello", "GET \x05hello\r\n");
    show("one", "GET \x01z\r\n");
    show("short", "GET \x09hello\r\n");
    show("no line end", "GET \x05hello");
    show("no verb", "PUT \x05hello\r\n");
    return 0;
}
