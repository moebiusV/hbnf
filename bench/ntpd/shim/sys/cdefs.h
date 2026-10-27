/* The few BSD <sys/cdefs.h> names OpenBSD's log.h and ntpd.h use, added to the system's own. */
#ifndef BENCH_CDEFS_H
#define BENCH_CDEFS_H
#include_next <sys/cdefs.h>
#ifndef __dead
#define __dead __attribute__((__noreturn__))
#endif
#ifndef __unused
#define __unused __attribute__((__unused__))
#endif
#ifndef __BEGIN_DECLS
#define __BEGIN_DECLS
#define __END_DECLS
#endif
#ifndef __packed
#define __packed __attribute__((__packed__))
#endif
#endif
