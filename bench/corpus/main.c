/* main.c -- time a generated parser over a corpus's own good files.  Built with
 * -DOUT_T="<root type>" after the generated parser.  Every file is parsed REPS times and every
 * tree is kept (so the memory is the trees', not one tree's), then the program prints
 * ok BYTES COUNT SUM MS RSS_KIB: COUNT is the number of parses that succeeded, SUM 0. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

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
    size_t nf = (size_t)argc - 2, i, total = 0, reps, r, ok = 0;
    char **text = malloc(nf * sizeof *text);
    size_t *len = malloc(nf * sizeof *len);
    struct timespec t0, t1;
    struct rusage ru;
    OUT_T *trees;
    char err[512];
    size_t line, col;
    double ms;
    if (argc < 3) return 2;
    reps = (size_t)atol(argv[1]);
    for (i = 0; i < nf; i++) {
        text[i] = slurp(argv[i + 2], &len[i]);
        if (!text[i]) return 2;
        total += len[i];
    }
    trees = calloc(nf * reps, sizeof *trees);
    if (!trees) return 2;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (r = 0; r < reps; r++)
        for (i = 0; i < nf; i++)
            if (parse_text(text[i], &trees[r * nf + i], err, sizeof err, &line, &col)) ok++;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    getrusage(RUSAGE_SELF, &ru);
    printf("%s %zu %zu 0 %.2f %ld\n", ok == nf * reps ? "ok" : "FAIL", total * reps, ok, ms, ru.ru_maxrss);
    return ok == nf * reps ? 0 : 1;
}
