/* stubs.c -- the parts of pfctl that sbin/pfctl/parse.y calls and a parse benchmark does not need.
 * Written for this harness; OpenBSD's pfctl.c, pfctl_parser.c and friends are not used.
 *
 * What it does keep real: pfctl_add_rule copies the finished rule and appends it to a list, as
 * pfctl's does (it callocs a rule, memcpys it, TAILQ_INSERT_TAILs it); host() and ifa_lookup()
 * answer for address and interface literals with a node_host, as pfctl's do before they would
 * ever need getaddrinfo or the kernel. */
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <md5.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <net/if.h>
#include <netinet/ip.h>
#include <net/pfvar.h>
#include "pfctl_parser.h"
#include "pfctl.h"

long long strtonum(const char *s, long long lo, long long hi, const char **err) {
	char *end; long long v;
	errno = 0; v = strtoll(s, &end, 10);
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
int sysctl(const int *a, unsigned b, void *c, size_t *d, void *e, size_t f) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return -1; }
int uid_from_user(const char *n, uid_t *u) { (void)n; *u = 0; return 0; }
int gid_from_group(const char *n, gid_t *g) { (void)n; *g = 0; return 0; }
uint32_t arc4random(void) { return 4; }
void MD5Init(MD5_CTX *c) { (void)c; }
void MD5Update(MD5_CTX *c, const void *p, unsigned n) { (void)c;(void)p;(void)n; }
void MD5Final(unsigned char d[16], MD5_CTX *c) { (void)c; memset(d, 0, 16); }
void err(int e, const char *f, ...) { (void)f; exit(e); }
void errx(int e, const char *f, ...) { (void)f; exit(e); }
void warn(const char *f, ...) { (void)f; }
void warnx(const char *f, ...) { (void)f; }

/* ---- what the parse leaves behind: the rules ---- */
struct rnode { struct rnode *next; struct pf_rule r; };
static struct rnode *rhead, **rtail = &rhead;
unsigned long n_rules, sum_ports;
void pfctl_add_rule(struct pfctl *pf, struct pf_rule *r) {
	struct rnode *n = calloc(1, sizeof *n);
	(void)pf;
	memcpy(&n->r, r, sizeof n->r);
	*rtail = n; rtail = &n->next;
	n_rules++;
	sum_ports += ntohs(r->src.port[0]);
}

static struct node_host *lit(const char *s, int af) {
	struct node_host *h = calloc(1, sizeof *h);
	h->af = af;
	if (af == AF_INET) inet_pton(AF_INET, s, &h->addr.v.a.addr.v4);
	h->next = NULL; h->tail = h;
	return h;
}
struct node_host *host(const char *s, int opts) {
	(void)opts;
	if (strchr(s, ':')) return lit(s, AF_INET6);
	return lit(s, AF_INET);
}
struct node_host *ifa_exists(const char *n) { struct node_host *h = lit("0.0.0.0", AF_INET); h->ifname = strdup(n); return h; }
struct node_host *ifa_lookup(const char *n, int f) { (void)f; return ifa_exists(n); }
unsigned int ifa_nametoindex(const char *n) { (void)n; return 1; }
char *ifa_indextoname(unsigned int i, char *b) { (void)i; strcpy(b, "em0"); return b; }
FILE *pfctl_fopen(const char *n, const char *m) { return fopen(n, m); }

/* pfctl_parser.c's own parse_flags: "S/SA" -> flags | mask << 8 */
int parse_flags(char *s) {
	const char *tcpflags = "FSRPAUEW";
	const char *p, *q = s;
	int f = 0, m = 0;
	for (; *q && *q != '/'; q++) {
		if ((p = strchr(tcpflags, *q)) == NULL) return -1;
		f |= 1 << (p - tcpflags);
	}
	if (*q == '/') {
		for (q++; *q; q++) {
			if ((p = strchr(tcpflags, *q)) == NULL) return -1;
			m |= 1 << (p - tcpflags);
		}
	} else m = 0xff;
	return f | m << 8;
}
