/* main-pfctl.c -- time pfctl's parse.y (parse_config) over a file; print ok BYTES COUNT SUM MS RSS_KIB. */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/ip.h>
#include <net/pfvar.h>
#include "pfctl_parser.h"
#include "pfctl.h"
extern int parse_config(char *, struct pfctl *);
extern unsigned long n_rules, sum_ports;
int main(int argc, char **argv) {
	static struct pfctl pf; static struct pf_anchor root; struct timespec t0, t1; struct rusage ru; double ms; int rc;
	if (argc < 2) return 2;
	pf.astack[0] = pf.anchor = &root;   /* pfctl.c main() sets up the root anchor the same way */
	
	clock_gettime(CLOCK_MONOTONIC, &t0);
	rc = parse_config(argv[1], &pf);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
	getrusage(RUSAGE_SELF, &ru);
	printf("%s 0 %lu %lu %.2f %ld\n", rc == 0 ? "ok" : "FAIL", n_rules, sum_ports, ms, ru.ru_maxrss);
	return rc == 0 ? 0 : 1;
}
