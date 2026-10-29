/* time_c.c -- time parse_text of the generated C parser over many files.
 *
 * Built by concatenating the generated parser ahead of this file, with -DOUT_T=<the root's type>.
 * Every file is read first; the clock is around the parses alone.  Prints
 * "MS BYTES REFUSED RSS_KIB": the milliseconds for all the files, their bytes, how many the
 * parser refused, and the peak memory.  Built with -DTAPE for a parser that writes a tape
 * (--layout=tape, -I runtime): the tape is made room for once and starts again for each file.  */
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
    int i, refused = 0;
    size_t total = 0;
    char **text = (char **)malloc(sizeof(char *) * (size_t)argc);
    struct timespec t0, t1;
    struct rusage ru;
    for (i = 1; i < argc; i++) {
        size_t n;
        text[i] = slurp(argv[i], &n);
        if (!text[i]) return 2;
        total += n;
    }
#ifdef TAPE
    { size_t most = 0; for (i = 1; i < argc; i++) { size_t m = strlen(text[i]); if (m > most) most = m; } tape_reserve(most); }
#endif
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (i = 1; i < argc; i++) {
        char err[1024];
        size_t line, col;
        OUT_T tree;
#ifdef TAPE
        tape_n = 0;
#endif
        if (!parse_text(text[i], &tree, err, sizeof err, &line, &col)) refused++;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    getrusage(RUSAGE_SELF, &ru);
    printf("%.2f %zu %d %ld\n", (double)(t1.tv_sec - t0.tv_sec) * 1000.0 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6,
           total, refused, ru.ru_maxrss);
    return 0;
}
