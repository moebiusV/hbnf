#include <stdio.h>
#include <string.h>

/* server.c is the generated declarations + parser, concatenated. */
#include "server.c"

static const char *lines[] = {
    "example.com",
    "on wg0 port oops",
    "/var/www",
    "www",
    "yes",
};

static token_t malformed[] = {
    { TOK_STR,  "example.com", 1, 1 },
    { TOK_ATOM, "on", 2, 1 },
    { TOK_ATOM, "wg0", 2, 4 },
    { TOK_ATOM, "port", 2, 8 },
    { TOK_ATOM, "oops", 2, 13 },
    { TOK_EOF,  "", 5, 1 },
};

static token_t valid[] = {
    { TOK_STR,  "example.com", 1, 1 },
    { TOK_ATOM, "on", 2, 1 },
    { TOK_ATOM, "wg0", 2, 4 },
    { TOK_ATOM, "port", 2, 8 },
    { TOK_INT,  "443", 2, 13 },
    { TOK_STR,  "/var/www", 3, 1 },
    { TOK_STR,  "www", 4, 1 },
    { TOK_ATOM, "yes", 5, 1 },
    { TOK_EOF,  "", 5, 1 },
};

static void run(const char *what, token_t *toks, size_t n) {
    server_t out = {0};
    char err[512];
    size_t line = 0, col = 0;
    if (parse_config(toks, n, &out, lines, 5, err, sizeof err, &line, &col)) {
        printf("== %s: OK (name=%s port=%u)\n", what,
               out.name ? out.name : "?", (unsigned)out.listen.port);
    } else {
        printf("== %s: error in config line %zu:\n%s\n", what, line, err);
    }
}

int main(void) {
    run("valid", valid, sizeof valid / sizeof valid[0]);
    run("malformed", malformed, sizeof malformed / sizeof malformed[0]);
    return 0;
}
