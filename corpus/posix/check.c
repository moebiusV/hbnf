/* check.c -- for the POSIX shell grammar: read each file named on the command line and say
   whether the generated parser accepts it.  Built after the generated parser (cat shell.c check.c).
   Prints "ok FILE" or "bad FILE: MESSAGE" for each, and exits 1 if any was refused. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    char *b;
    long l;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); l = ftell(f); fseek(f, 0, SEEK_SET);
    b = (char *)malloc((size_t)l + 1);
    *n = fread(b, 1, (size_t)l, f);
    b[*n] = 0;
    fclose(f);
    return b;
}

int main(int argc, char **argv) {
    int bad = 0, i;
    for (i = 1; i < argc; i++) {
        size_t len;
        char *text = slurp(argv[i], &len);
        char err[1024];
        size_t line, col;
        OUT_T tree;
        if (!text) { printf("bad %s: cannot read\n", argv[i]); bad = 1; continue; }
        if (parse_text(text, &tree, err, sizeof err, &line, &col)) printf("ok %s\n", argv[i]);
        else { char *nl = strchr(err, '\n'); if (nl) *nl = 0; printf("bad %s: %s\n", argv[i], err); bad = 1; }
        free(text);
    }
    return bad;
}
