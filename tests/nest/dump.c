/* dump.c: for each file named, "ok" and the text the tree writes, or "bad" and the first line of the message.
   Built with -DOUT_T=... -DWRITE=write_<root>; the generated parser is included above it. */
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        FILE *f = fopen(argv[i], "rb");
        char *b, err[512];
        long l;
        size_t line, col, n;
        OUT_T t;
        if (!f) return 2;
        fseek(f, 0, SEEK_END); l = ftell(f); fseek(f, 0, SEEK_SET);
        b = (char *)malloc((size_t)l + 1);
        b[fread(b, 1, (size_t)l, f)] = 0;
        fclose(f);
        if (!parse_text(b, &t, err, sizeof err, &line, &col)) {
            char *nl = strchr(err, '\n');
            if (nl) *nl = 0;
            printf("%d bad %zu:%zu %s\n", i, line, col, err);
        } else {
            n = WRITE(&t, NULL, 0);
            char *w = (char *)malloc(n + 1);
            WRITE(&t, w, n + 1);
            printf("%d ok %s\n", i, w);
            free(w);
        }
        free(b);
    }
    return 0;
}
