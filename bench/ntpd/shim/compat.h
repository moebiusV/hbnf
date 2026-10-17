/* compat.h — what OpenBSD's ntpd parse.y expects of its platform, for building
 * it unchanged on Linux.  Force-included (-include) so the real parse.y and
 * ntpd.h are compiled as published.  Nothing here changes what the parser
 * does; it only supplies BSD names.
 */
#ifndef BENCH_COMPAT_H
#define BENCH_COMPAT_H
#include <stddef.h>
#include <sys/cdefs.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

/* BSD sockaddr length members: write-only in parse.y. */
#define sin_len  sin_zero[0]
#define sin6_len sin6_flowinfo

#ifndef RT_TABLEID_MAX
#define RT_TABLEID_MAX 255
#endif

#include <sys/queue.h>
#ifndef TAILQ_HEAD_INITIALIZER
#define TAILQ_HEAD_INITIALIZER(head) { NULL, &(head).tqh_first }
#endif

long long strtonum(const char *, long long, long long, const char **);
size_t strlcpy(char *, const char *, size_t);
size_t strlcat(char *, const char *, size_t);
#endif
