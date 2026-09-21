#include <stdio.h>
#include <string.h>

/* server.c is the generated declarations + lexer + parser, concatenated. */
#include "server.c"

static const char *valid = "\"example.com\"\n"
                           "on wg0 port 443\n"
                           "\"/var/www\"\n"
                           "\"www\"\n"
                           "yes\n";

static const char *bad = "\"example.com\"\n"
                         "on wg0 port oops\n"
                         "\"/var/www\"\n"
                         "\"www\"\n"
                         "yes\n";

static void run(const char *what, const char *text) {
    server_t out = {0};
    char err[512];
    size_t line = 0, col = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col)) {
        printf("== %s: OK (name=%s port=%u)\n", what,
               out.name ? out.name : "?", (unsigned)out.listen.port);
    } else {
        printf("== %s: error in config line %zu:\n%s\n", what, line, err);
    }
}

int main(void) {
    run("valid", valid);
    run("malformed", bad);
    return 0;
}
