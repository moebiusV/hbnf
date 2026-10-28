/* time_hbnf.c -- time parse_file over a pfctl config and count the
 * rules it built; print ok BYTES COUNT SUM MS RSS_KIB.  Built by concatenating the generated
 * parser ahead of this file.  SUM is 0: the tree is checked by its rule count only. */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
int main(int argc, char **argv) {
	struct timespec t0, t1; struct rusage ru; double ms; int ok; unsigned long n = 0;
	struct ruleset_list root; char err[512]; size_t el, ec;
	if (argc < 2) return 2;
	memset(&root, 0, sizeof root);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	ok = parse_file(argv[1], &root, err, sizeof err, &el, &ec) ? 0 : -1;
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
	if (ok == 0) { struct ruleset_s *r; TAILQ_FOREACH(r, &root, _link) n++; }
	getrusage(RUSAGE_SELF, &ru);
	printf("%s 0 %lu 0 %.2f %ld\n", ok == 0 ? "ok" : "FAIL", n, ms, ru.ru_maxrss);
	return ok == 0 ? 0 : 1;
}
