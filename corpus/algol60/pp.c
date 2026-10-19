/* An ALGOL 60 pretty-printer, on the parser hbnf generates from algol60.hbnf.
 *
 *   hbnf corpus/algol60/algol60.hbnf --backend=c --writer > a60.c
 *   cc -include a60.c -o pp corpus/algol60/pp.c        (or: sh tests/algol60-pp.sh)
 *   ./pp program.a60 > pretty.a60
 *
 * The parser reads the program into a tree (comments are nodes of it), and the
 * generated writer prints the tree back, token by token.  All this file does is
 * say what goes before each token: a newline and an indent, a blank, or nothing.
 * The grammar is not repeated here.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int depth;               /* how many BEGINs are open */
    int brackets;            /* [ ] nesting: a : inside is a bound pair, not a label */
    int junk;                /* inside the text after END */
    char prev[32], prev2[32];
    char out[128];
} pp_t;

static int is(const char *a, const char *b) { return strcmp(a, b) == 0; }
static int in(const char *s, const char *const *set) {
    for (; *set; set++) if (is(s, *set)) return 1;
    return 0;
}
/* a token that ends an operand: a name, a number, a string, ) or ] */
static int operand_end(const char *s) {
    char c = s[0] ? s[strlen(s) - 1] : 0;
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
        || c == ')' || c == ']' || c == '"' || (c == '\'' && !is(s, "'THEN'") && !is(s, "'ELSE'")
        && !is(s, "'DO'") && !is(s, "'BEGIN'")) ? 1 : 0;
}

static const char *newline(pp_t *p) {
    int n = p->depth < 0 ? 0 : p->depth;
    if (n > 30) n = 30;
    p->out[0] = '\n';
    memset(p->out + 1, ' ', 4 * (size_t)n);
    p->out[1 + 4 * n] = 0;
    return p->out;
}

static const char *layout(void *ctx, int ev, const char *s) {
    static const char *const opening[] = { "(", "[", NULL };
    static const char *const closing[] = { ")", "]", ";", ",", NULL };
    static const char *const body[] = { "'THEN'", "'ELSE'", "'DO'", NULL };
    pp_t *p = ctx;
    const char *sep;
    int remark = strncmp(s, "'COMMENT'", 9) == 0;   /* a comment is one token, ending in ; */

    if (ev == 1 || ev == 2) {
        if (is(s, "end_junk")) p->junk = ev == 1;
        return NULL;
    }
    if (p->junk) {                       /* the text after END, as it came */
        sep = is(p->prev, "'END'") ? " " : "";
    } else if (!p->prev[0]) {
        sep = "";
    } else if (remark) {                 /* a comment stands on a line of its own */
        sep = newline(p);
    } else if (is(s, "'END'")) {
        p->depth--;
        sep = newline(p);
    } else if (is(p->prev, "'BEGIN'") || is(p->prev, ";")) {
        sep = newline(p);
    } else if (is(s, "'ELSE'")) {
        sep = newline(p);
    } else if (is(s, "'BEGIN'") && in(p->prev, body)) {
        sep = " ";
    } else if (in(s, closing) || in(p->prev, opening)) {
        sep = "";
    } else if (is(s, "(") || is(s, "[")) {
        sep = operand_end(p->prev) && p->prev[0] != '\'' ? "" : " ";
    } else if (is(s, ":")) {
        sep = "";
    } else if ((is(p->prev, "+") || is(p->prev, "-")) && !operand_end(p->prev2)) {
        sep = "";                        /* a sign, not an operator */
    } else if (is(p->prev, ":")) {
        sep = p->brackets ? "" : " ";
    } else {
        sep = " ";
    }
    if (is(s, "'BEGIN'")) p->depth++;
    if (is(s, "[")) p->brackets++;
    if (is(s, "]") && p->brackets) p->brackets--;
    strncpy(p->prev2, p->prev, sizeof p->prev2 - 1);
    strncpy(p->prev, remark ? ";" : s, sizeof p->prev - 1);
    p->prev[sizeof p->prev - 1] = 0;
    return sep;
}

static char *slurp(FILE *f) {
    size_t n = 0, cap = 1 << 16;
    char *b = malloc(cap);
    size_t got;
    if (!b) exit(2);
    while ((got = fread(b + n, 1, cap - n - 1, f)) > 0) {
        n += got;
        if (n + 1 >= cap) { cap *= 2; b = realloc(b, cap); if (!b) exit(2); }
    }
    b[n] = 0;
    return b;
}

/* Parse text and write it as the printer lays it out; NULL when it does not parse. */
static char *pretty(const char *text, char *err, size_t errlen) {
    program_t tree;
    size_t line, col, n;
    char *out;
    pp_t st;

    if (!parse_text(text, &tree, err, errlen, &line, &col)) return NULL;
    hbnf_write_layout = layout;
    hbnf_write_layout_ctx = &st;
    memset(&st, 0, sizeof st);                 /* the first pass measures, the second writes */
    n = write_program(&tree, NULL, 0);
    if (n == (size_t)-1) { snprintf(err, errlen, "%s", hbnf_write_error); return NULL; }
    out = malloc(n + 2);
    if (!out) exit(2);
    memset(&st, 0, sizeof st);
    write_program(&tree, out, n + 1);
    out[n] = '\n';
    out[n + 1] = 0;
    return out;
}

int main(int argc, char **argv) {
    char err[512], *text, *a, *b;
    FILE *f = stdin;
    int check = argc > 1 && is(argv[1], "-c");      /* -c: print it twice over, as a test */

    if (argc > 1 + check) {
        f = fopen(argv[1 + check], "rb");
        if (!f) { perror(argv[1 + check]); return 2; }
    }
    text = slurp(f);
    a = pretty(text, err, sizeof err);
    if (!a) { fprintf(stderr, "pp: %s\n", err); return 1; }
    if (check) {                          /* what it printed must read, and print the same */
        b = pretty(a, err, sizeof err);
        if (!b) { fprintf(stderr, "pp: the output does not parse: %s\n%s", err, a); return 1; }
        if (strcmp(a, b)) { fprintf(stderr, "pp: not idempotent\n--- first\n%s--- second\n%s", a, b); return 1; }
        return 0;
    }
    fputs(a, stdout);
    return 0;
}
