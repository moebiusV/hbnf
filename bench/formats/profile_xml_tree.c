/* loop.c -- parse one XML file N times in one process, the tree freed between parses (free_document).
 * argv: file N. Prints min and median ms of parse_text alone.  Built after the generated tree parser, -DOUT_T=document_t. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static int cmpd(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
int main(int argc, char **argv) {
    FILE *f; char *buf, err[512]; long len; size_t line, col; int n = argc > 2 ? atoi(argv[2]) : 200, i;
    double *t; struct timespec t0, t1;
    if (argc < 2 || !(f = fopen(argv[1], "rb"))) return 2;
    fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
    buf = malloc(len + 1); if (fread(buf, 1, len, f) != (size_t)len) return 2; buf[len] = 0; fclose(f);
    t = malloc(sizeof(double) * n);
    for (i = 0; i < n; i++) {
        OUT_T out; int ok;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        ok = parse_text(buf, &out, err, sizeof err, &line, &col);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        if (!ok) { fprintf(stderr, "%s\n", err); return 1; }
        t[i] = (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
        free_document(&out);
    }
    qsort(t, n, sizeof(double), cmpd);
    printf("loop n=%d min %.3f med %.3f ms\n", n, t[0], t[n / 2]);
    return 0;
}
