#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include "ntpd.h"

/* Canonical dump of the parse-built conf: the deep-compare walk, as a
   serializer.  Every scalar/array prints by value, every string by content,
   every list in order, every pointer by what it points to — never addresses,
   TAILQ links or padding.  Two parsers are a drop-in match iff their dumps
   are byte-identical. */

static void dump_sa(const char *what, const struct sockaddr_storage *ss) {
    printf("  %s fam=%u", what, ss->ss_family);
    if (ss->ss_family == AF_INET) {
        const struct sockaddr_in *s = (const void *)ss;
        char b[INET_ADDRSTRLEN];
        printf(" addr=%s port=%u",
               inet_ntop(AF_INET, &s->sin_addr, b, sizeof b), ntohs(s->sin_port));
    } else if (ss->ss_family == AF_INET6) {
        const struct sockaddr_in6 *s = (const void *)ss;
        char b[INET6_ADDRSTRLEN];
        printf(" addr=%s port=%u scope=%u",
               inet_ntop(AF_INET6, &s->sin6_addr, b, sizeof b),
               ntohs(s->sin6_port), s->sin6_scope_id);
    } else {
        printf(" addr=?");
    }
    printf("\n");
}

static void dump_addr(const char *what, const struct ntp_addr *a) {
    int i = 0;
    for (; a; a = a->next, i++) {
        printf("    %s[%d] notauth=%d\n", what, i, a->notauth);
        dump_sa("      sa", &a->ss);
    }
    printf("    %s_count=%d\n", what, i);
}

void dump_ntpd_conf(const struct ntpd_conf *c) {
    const struct listen_addr *la;
    const struct ntp_peer *p;
    const struct ntp_conf_sensor *s;
    const struct constraint *ct;

    printf("trusted_peers=%u trusted_sensors=%u\n",
           c->trusted_peers, c->trusted_sensors);

    printf("listen_addrs\n");
    TAILQ_FOREACH(la, &c->listen_addrs, entry) {
        printf("  fd=%d rtable=%d\n", la->fd, la->rtable);
        dump_sa("  sa", &la->sa);
    }

    printf("ntp_peers\n");
    TAILQ_FOREACH(p, &c->ntp_peers, entry) {
        printf("  weight=%u trusted=%u pool=%u name=%s state=%d\n",
               p->weight, p->trusted, p->addr_head.pool,
               p->addr_head.name ? p->addr_head.name : "(null)", (int)p->state);
        dump_sa("  query4", (const void *)&p->query_addr4);
        dump_sa("  query6", (const void *)&p->query_addr6);
        dump_addr("addr", p->addr);
    }

    printf("ntp_conf_sensors\n");
    TAILQ_FOREACH(s, &c->ntp_conf_sensors, entry) {
        printf("  device=%s refstr=%s correction=%d stratum=%u weight=%u trusted=%u\n",
               s->device ? s->device : "(null)", s->refstr ? s->refstr : "(null)",
               s->correction, s->stratum, s->weight, s->trusted);
    }

    printf("constraints\n");
    TAILQ_FOREACH(ct, &c->constraints, entry) {
        printf("  pool=%u name=%s path=%s state=%d\n",
               ct->addr_head.pool,
               ct->addr_head.name ? ct->addr_head.name : "(null)",
               ct->addr_head.path ? ct->addr_head.path : "(null)",
               (int)ct->state);
        dump_addr("addr", ct->addr);
    }
}
