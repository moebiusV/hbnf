#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include "ntpd.h"
#include "log.h"

/* ---- the byte-identity harness glue ---- */

struct ntpd_conf *conf = NULL;
extern void dump_ntpd_conf(const struct ntpd_conf *);

/* constraint_add lives in constraint.c, which drags in imsg/tls; the parse
 * only needs this one TAILQ insert. */
void constraint_add(struct constraint *cstr) {
    TAILQ_INSERT_TAIL(&conf->constraints, cstr, entry);
}

/* OpenBSD's strtonum: strtoll with [minval,maxval] bounds and an errstr.
 * parse.y's lexer uses it to read NUMBER tokens. */
long long strtonum(const char *numstr, long long minval, long long maxval,
                   const char **errstrp) {
    char *ep;
    long long val;
    if (errstrp) *errstrp = NULL;
    if (numstr == NULL || *numstr == '\0') { if (errstrp) *errstrp = "invalid"; return 0; }
    errno = 0;
    val = strtoll(numstr, &ep, 10);
    if (ep == numstr || *ep != '\0' || errno == ERANGE) {
        if (errstrp) *errstrp = "invalid"; return 0;
    }
    if (val < minval) { if (errstrp) *errstrp = "too small"; return 0; }
    if (val > maxval) { if (errstrp) *errstrp = "too large"; return 0; }
    return val;
}

int main(int argc, char **argv) {
    struct ntpd_conf c;
    if (argc != 2) { fprintf(stderr, "usage: %s config\n", argv[0]); return 2; }
    memset(&c, 0, sizeof c);
    log_init(LOG_TO_STDERR, 0, 24);   /* LOG_DAEMON */
    if (parse_config(argv[1], &c) != 0) {
        fprintf(stderr, "parse_config failed\n");
        return 1;
    }
    dump_ntpd_conf(&c);
    return 0;
}
