/* main-parsey.c — time OpenBSD's parse_config() over a config file and count
 * what it built.  Output contract as bench/drv/timing.h: COUNT is the number
 * of `sensor` lines the parse produced, SUM the sum of their `stratum` values
 * (the generator writes one per sensor, so both can be checked). */
#include <string.h>
#include "timing.h"
#include "ntpd.h"


int main(int argc, char **argv) {
	struct ntpd_conf lconf;
	struct ntp_conf_sensor *s;
	size_t len;
	long count = 0;
	long long sum = 0;
	double t0, ms;
	int rc;

	if (argc < 2) return 2;
	free(bench_read(argv[1], &len));   /* size, and the file is in the page cache */
	memset(&lconf, 0, sizeof lconf);
	t0 = bench_now_ms();
	rc = parse_config(argv[1], &lconf);
	ms = bench_now_ms() - t0;
	TAILQ_FOREACH(s, &lconf.ntp_conf_sensors, entry) {
		count++;
		sum += s->stratum;
	}
	return bench_report(rc == 0, len, count, sum, ms);
}
