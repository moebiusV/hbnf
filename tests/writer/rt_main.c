/* The writer's gate (tests/writer.sh): for each file, parse it, write the tree,
   parse what was written, write again.  The first write must re-parse, and
   the second write must be the same text as the first (the writer is
   idempotent).  Built with -DOUT_T="..." -DWRITE=write_<root>. */
#include <stdio.h>

static char *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    char *b;
    long l;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);  l = ftell(f);  fseek(f, 0, SEEK_SET);
    b = (char *)malloc((size_t)l + 1);
    *n = fread(b, 1, (size_t)l, f);
    b[*n] = 0;
    fclose(f);
    return b;
}

static int roundtrip(const char *path) {
    OUT_T t1, t2;
    char err[512];
    size_t line, col, len, n1, n2;
    char *in = slurp(path, &len), *a, *b;
    if (!in) { printf("%s: FAIL (cannot read)\n", path); return 1; }
    if (!parse_text(in, &t1, err, sizeof err, &line, &col)) {
        printf("%s: SKIP (does not parse)\n", path);
        return 0;
    }
    n1 = WRITE(&t1, NULL, 0);
    if (n1 == (size_t)-1) {
        printf("%s: FAIL (cannot write: %s)\n", path, hbnf_write_error);
        return 1;
    }
    a = (char *)malloc(n1 + 1);
    WRITE(&t1, a, n1 + 1);
    if (!parse_text(a, &t2, err, sizeof err, &line, &col)) {
        printf("%s: FAIL (the written text does not parse: %s)\n", path, err);
        printf("--- written ---\n%s\n---\n", a);
        return 1;
    }
    n2 = WRITE(&t2, NULL, 0);
    b = (char *)malloc(n2 + 1);
    WRITE(&t2, b, n2 + 1);
    /* the same tree: the written text read back has the shape that was written */
    hbnf_write_trace = 1;
    {
        size_t m1 = WRITE(&t1, NULL, 0), m2 = WRITE(&t2, NULL, 0);
        char *c = (char *)malloc(m1 + 1), *d = (char *)malloc(m2 + 1);
        WRITE(&t1, c, m1 + 1);  WRITE(&t2, d, m2 + 1);
        hbnf_write_trace = 0;
        if (m1 != m2 || memcmp(c, d, m1)) {
            printf("%s: FAIL (the written text reads as a different tree)\n"
                   "--- before ---\n%s\n--- after ---\n%s\n--- text ---\n%s\n", path, c, d, a);
            return 1;
        }
    }
    if (n1 != n2 || memcmp(a, b, n1)) {
        printf("%s: FAIL (not idempotent)\n--- first ---\n%s\n--- second ---\n%s\n", path, a, b);
        return 1;
    }
    if (getenv("HBNF_SHOW")) printf("%s\n", a);
    printf("%s: ok (%zu bytes)\n", path, n1);
    return 0;
}

int main(int argc, char **argv) {
    int i, bad = 0;
    for (i = 1; i < argc; i++) bad += roundtrip(argv[i]);
    return bad != 0;
}
