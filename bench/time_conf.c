/* time_conf.c — time a parse_file call over a file, report peak RSS.
 *
 * Built by concatenating the generated parser (pfctl's grammar) ahead of this file; the parser
 * defines parse_file.  One parse
 * per process; section6.sh runs it five times and keeps the best wall time.
 * This is the paper's parse_file path: the `statements` driver reads the
 * file a block at a time.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

int main(int argc, char **argv) {
    struct timespec t0, t1;
    struct rusage ru;
    double ms;
    int ok;
    struct ruleset_list root;
    char err[512];
    size_t el, ec;

    if (argc < 2)
        return 2;

    memset(&root, 0, sizeof root);
    clock_gettime(CLOCK_MONOTONIC, &t0);
    ok = parse_file(argv[1], &root, err, sizeof err, &el, &ec) ? 0 : -1;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0
       + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;

    getrusage(RUSAGE_SELF, &ru);
    printf("%s %.2f %ld\n", ok == 0 ? "ok" : "FAIL", ms, ru.ru_maxrss);
    return ok == 0 ? 0 : 1;
}
