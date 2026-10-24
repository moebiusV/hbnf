/* timer.h -- what every driver of the library comparison shares: read the file, time one parse,
 * print "ok BYTES MS RSS_KIB" (or "FAIL ..." and exit 1), as bench/formats/time_format.c does. */
#ifndef TIMER_H
#define TIMER_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

static char *read_file(const char *path, long *len) {
    FILE *f = fopen(path, "rb");
    char *buf;
    if (!f) exit(2);
    fseek(f, 0, SEEK_END); *len = ftell(f); fseek(f, 0, SEEK_SET);
    buf = (char *)malloc(*len + 1);
    if (fread(buf, 1, *len, f) != (size_t)*len) exit(2);
    buf[*len] = 0; fclose(f);
    return buf;
}
static double now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}
static int report(int ok, long len, double t0, double t1, const char *why) {
    struct rusage ru;
    getrusage(RUSAGE_SELF, &ru);
    if (!ok) { fprintf(stderr, "%s\n", why ? why : "refused"); printf("FAIL %ld %.2f %ld\n", len, t1 - t0, ru.ru_maxrss); return 1; }
    printf("ok %ld %.2f %ld\n", len, t1 - t0, ru.ru_maxrss);
    return 0;
}
#endif
