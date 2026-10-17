/* The few BSD <sys/cdefs.h> names OpenBSD's log.h and ntpd.h use. */
#ifndef BENCH_CDEFS_H
#define BENCH_CDEFS_H
#define __dead __attribute__((__noreturn__))
#define __unused __attribute__((__unused__))
#define __BEGIN_DECLS
#define __END_DECLS
#define __packed __attribute__((__packed__))
#endif
