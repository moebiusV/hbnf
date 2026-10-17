/* timing.h — what every C driver shares: read the file, time one parse, report.
 *
 * Output contract (one line, the last two fields are time and peak RSS):
 *     ok BYTES COUNT SUM MS RSS_KIB
 * COUNT is the number of rules the parse produced and SUM the sum of their two
 * port numbers; run.sh checks both against what gen.sh wrote, so a parser that
 * stopped early or dropped a field is a failure, not a fast row.
 */
#ifndef BENCH_TIMING_H
#define BENCH_TIMING_H
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/resource.h>

static char *bench_read(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb");
    char *buf;
    long n;
    if (!f) exit(2);
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = (char *)malloc((size_t)n + 1);
    if (!buf || (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n)) exit(2);
    buf[n] = '\0';
    fclose(f);
    *len = (size_t)n;
    return buf;
}

static double bench_now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

static int bench_report(int ok, size_t bytes, long count, long long sum, double ms) {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    printf("%s %zu %ld %lld %.2f %ld\n", ok ? "ok" : "FAIL", bytes, count, sum,
           ms, ru.ru_maxrss);
    return ok ? 0 : 1;
}
#endif
