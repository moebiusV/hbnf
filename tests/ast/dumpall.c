/* dumpall.c: parses each file named on the command line and dumps its tree (the generated parser, built with
   --ast-tools, is included above this); -DROOT_T=the root type -DDUMP=the root's dump function.  Exit 1 if a file is
   refused or a dump is not as long as it said. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
    char err[512];
    size_t l, c;
    int i, bad = 0;
    for (i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        char *t;
        long n;
        ROOT_T v;
        if (!f) return 2;
        fseek(f, 0, SEEK_END);  n = ftell(f);  rewind(f);
        t = (char *)malloc(n + 1);
        if (fread(t, 1, n, f) != (size_t)n) return 2;
        t[n] = 0;  fclose(f);
        memset(&v, 0, sizeof v);
        if (!parse_text(t, &v, err, sizeof err, &l, &c)) {
            printf("%s: refused at %zu:%zu\n", argv[i], l, c);
            bad = 1;
        } else {
            size_t m = DUMP(&v, NULL, 0);
            char *b = (char *)malloc(m + 1);
            DUMP(&v, b, m + 1);
            if (strlen(b) != m) { printf("%s: the dump is not %zu bytes\n", argv[i], m); bad = 1; }
            free(b);
        }
        free(t);
    }
    return bad;
}
