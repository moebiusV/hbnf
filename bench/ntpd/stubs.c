/* stubs.c — the parts of ntpd that parse.y calls and a benchmark does not
 * need: logging, address lookup (the benchmark config uses address literals),
 * and the few libc functions musl lacks.  Written for this harness; OpenBSD's
 * ntpd.c, util.c and log.c are not used. */
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include "ntpd.h"

long long strtonum(const char *s, long long lo, long long hi, const char **err) {
	char *end;
	long long v;
	errno = 0;
	v = strtoll(s, &end, 10);
	if (*s == '\0' || *end != '\0') { if (err) *err = "invalid"; errno = EINVAL; return 0; }
	if (errno == ERANGE || v < lo) { if (err) *err = "too small"; errno = ERANGE; return 0; }
	if (v > hi) { if (err) *err = "too large"; errno = ERANGE; return 0; }
	if (err) *err = NULL;
	return v;
}
size_t strlcpy(char *d, const char *s, size_t n) {
	size_t l = strlen(s);
	if (n) { size_t c = l >= n ? n - 1 : l; memcpy(d, s, c); d[c] = '\0'; }
	return l;
}
size_t strlcat(char *d, const char *s, size_t n) {
	size_t dl = strnlen(d, n);
	return dl + strlcpy(d + dl, s, n > dl ? n - dl : 0);
}

void log_warn(const char *fmt, ...) { (void)fmt; }
void log_warnx(const char *fmt, ...) { (void)fmt; }
void log_info(const char *fmt, ...) { (void)fmt; }
void log_debug(const char *fmt, ...) { (void)fmt; }
void fatal(const char *fmt, ...) { (void)fmt; exit(1); }
void fatalx(const char *fmt, ...) { (void)fmt; exit(1); }

/* host(): the benchmark's addresses are literals, so no resolver. */
void host(const char *s, struct ntp_addr **hn) {
	struct ntp_addr *h;
	struct sockaddr_in *in;
	*hn = NULL;
	if (*s == '*') return;
	if ((h = calloc(1, sizeof *h)) == NULL) return;
	in = (struct sockaddr_in *)&h->ss;
	if (inet_pton(AF_INET, s, &in->sin_addr) == 1) {
		in->sin_family = AF_INET;
		*hn = h;
		return;
	}
	free(h);
}
int host_dns(const char *s, int notauto, struct ntp_addr **hn) {
	(void)notauto;
	host(s, hn);
	return *hn != NULL;
}

/* new_sensor() and new_constraint() as ntpd's config.c makes them. */
struct ntp_conf_sensor *new_sensor(char *device) {
	struct ntp_conf_sensor *s = calloc(1, sizeof *s);
	if (s == NULL) fatal("ntp_conf_sensor calloc");
	s->device = device;
	s->weight = 1;
	return s;
}
struct constraint *new_constraint(void) {
	struct constraint *c = calloc(1, sizeof *c);
	if (c == NULL) fatal("constraint calloc");
	return c;
}

/* ntpd's global configuration pointer, and the two list helpers parse.y calls. */
struct ntpd_conf *conf;
struct ntp_peer *new_peer(void) {
	struct ntp_peer *p = calloc(1, sizeof *p);
	if (p == NULL) fatal("new_peer calloc");
	return p;
}
void constraint_add(struct constraint *c) {
	TAILQ_INSERT_TAIL(&conf->constraints, c, entry);
}
