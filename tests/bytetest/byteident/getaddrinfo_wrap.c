#include <stdint.h>
#include <netdb.h>

int __real_getaddrinfo(const char *, const char *, const struct addrinfo *,
                       struct addrinfo **);

/* OpenBSD's sockaddr_* prefix the family with a one-byte length (sin_len /
 * sin6_len); glibc's do not, and the two systems disagree on AF_INET6 (10 vs
 * 24).  Rewrite glibc's results in place into the OpenBSD layout, so the
 * daemon's host()/host_dns() (compiled against OpenBSD headers) read them
 * correctly.  Port and address bytes sit at the same offsets in both. */
int __wrap_getaddrinfo(const char *hostname, const char *servname,
                       const struct addrinfo *hints, struct addrinfo **res) {
    int r = __real_getaddrinfo(hostname, servname, hints, res);
    if (r == 0) {
        struct addrinfo *ai;
        for (ai = *res; ai; ai = ai->ai_next) {
            uint8_t *p = (uint8_t *)ai->ai_addr;
            uint8_t fam = (ai->ai_family == 10) ? 24 : (uint8_t)ai->ai_family;
            ai->ai_family = fam;
            p[0] = (uint8_t)ai->ai_addrlen;  /* sin_len / sin6_len */
            p[1] = fam;                      /* sin_family / sin6_family */
        }
    }
    return r;
}

int __real_inet_pton(int, const char *, void *);

/* The daemon passes OpenBSD's AF_INET6 (24) to glibc's inet_pton, which only
 * knows 10 and fails, so every IPv6 literal looked invalid.  in6_addr has
 * the same 16 bytes on both systems. */
int __wrap_inet_pton(int af, const char *src, void *dst) {
    return __real_inet_pton(af == 24 ? 10 : af, src, dst);
}
