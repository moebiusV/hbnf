#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>

/* bitcharts OUTDIR < grammar.hbnf : read a grammar of leaf rules, write one SVG per leaf */
#include "bitcharts.c"
int main (int argc, char **argv)
{
    char err[512]; size_t line = 0, col = 0, cap = 1 << 20, n = 0, r;
    char *buf = malloc (cap); file_t out;
    if (argc > 1) outdir = argv[1];
    while ((r = fread (buf + n, 1, cap - n - 2, stdin)) > 0) { n += r; if (n + 2 >= cap) buf = realloc (buf, cap *= 2); }
    buf[n] = 0;
    if (!parse_text (buf, &out, err, sizeof err, &line, &col)) { fprintf (stderr, "parse error at %zu:%zu: %s\n", line, col, err); return 1; }
    fprintf (stderr, "bitcharts: %d charts\n", nleaf);
    if (argc > 2 && !strcmp (argv[2], "tables")) tables_out (stdout);
    return 0;
}
