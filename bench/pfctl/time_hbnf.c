/* time_hbnf.c -- time parse_config (hbnf's --conf wrapper) over a pfctl config and count the
 * rules it built; print ok BYTES COUNT SUM MS RSS_KIB.  Built by concatenating the generated
 * conf.c ahead of this file.  SUM is 0: the tree is checked by its rule count only. */
#include <stdio.h>
#include <time.h>
#include <sys/resource.h>
#include "conf.h"
int main(int argc, char **argv) {
	struct timespec t0, t1; struct rusage ru; double ms; int ok; unsigned long n = 0;
	if (argc < 2) return 2;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	ok = parse_config(argv[1]);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
	if (ok == 0) { struct ruleset_s *r; TAILQ_FOREACH(r, conf_ptr(), _link) n++; }
	getrusage(RUSAGE_SELF, &ru);
	printf("%s 0 %lu 0 %.2f %ld\n", ok == 0 ? "ok" : "FAIL", n, ms, ru.ru_maxrss);
	return ok == 0 ? 0 : 1;
}
