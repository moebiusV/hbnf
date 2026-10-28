/* time_tape.c -- time parse_text of the JSON parser that writes a tape (corpus/json/json-tape.hbnf).
 *
 * Built like time_format.c: the generated parser ahead of this file, -DOUT_T=<the root's type>.
 * The file is read first; the clock is around the parse alone, one parse per process.  The tape
 * is checked afterwards, outside the clock: it must hold something, and every object and array on
 * it must link to a position inside it.  Prints "ok BYTES MS RSS_KIB".
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
    FILE *f;
    char *buf, err[512];
    long len;
    size_t line, col, i;
    OUT_T out;
    struct timespec t0, t1;
    struct rusage ru;
    double ms;
    int ok;

    if (argc < 2 || !(f = fopen(argv[1], "rb"))) return 2;
    fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
    buf = malloc(len + 1);
    if (fread(buf, 1, len, f) != (size_t)len) return 2;
    buf[len] = 0; fclose(f);
    tape_text = buf;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    ok = parse_text(buf, &out, err, sizeof err, &line, &col);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
    getrusage(RUSAGE_SELF, &ru);
    if (ok && tape_n == 0) { strcpy(err, "the tape is empty"); ok = 0; }
    for (i = 0; ok && i < tape_n; i += 2)
        if ((tape[i] == T_OBJ || tape[i] == T_ARR) && (tape[i + 1] <= i || tape[i + 1] > tape_n)) {
            strcpy(err, "a link leaves the tape"); ok = 0;
        }
    if (!ok) { fprintf(stderr, "%s\n", err); printf("FAIL %ld %.2f %ld\n", len, ms, ru.ru_maxrss); return 1; }
    printf("ok %ld %.2f %ld\n", len, ms, ru.ru_maxrss);
    return 0;
}
