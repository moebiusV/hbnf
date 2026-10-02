/* time_text.c — time a parse_text call over a whole file, report peak RSS.
 *
 * Built by concatenating the generated toy parser ahead of this file:
 * the parser defines `parse_text(const char *, struct config_list *, …)`.
 * One parse per process; section6.sh runs it five times and keeps the best
 * wall time.  The whole input is read into memory (the paper's parse_text
 * path), so peak RSS includes the text.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

#include "parser.c"

int main(int argc, char **argv) {
    FILE *f;
    long len;
    char *buf;
    struct config_list out;
    char err[512];
    size_t l = 0, c = 0;
    struct timespec t0, t1;
    struct rusage ru;
    double ms;
    int ok;

    if (argc < 2)
        return 2;
    f = fopen(argv[1], "rb");
    if (!f)
        return 2;
    fseek(f, 0, SEEK_END);
    len = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = (char *)malloc((size_t)len + 1);
    if (len > 0 && fread(buf, 1, (size_t)len, f) != (size_t)len)
        return 2;
    buf[len] = '\0';
    fclose(f);

    clock_gettime(CLOCK_MONOTONIC, &t0);
    ok = parse_text(buf, &out, err, sizeof err, &l, &c);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0
       + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;

    getrusage(RUSAGE_SELF, &ru);
    printf("%s %zu %.2f %ld\n", ok ? "ok" : "FAIL",
           (size_t)len, ms, ru.ru_maxrss);
    return ok ? 0 : 1;
}
