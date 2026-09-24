/* unwind-ident.sh's shims: OpenBSD libc-internal names glibc spells
   differently (see ../ntpd-shims.c, which has these and ntpd's own). */
#include <stdio.h>
#include <string.h>

extern int *__errno_location(void);
int *__errno(void) { return __errno_location(); }

/* OpenBSD stdio spells stdin/stdout/stderr as __stdin/... arrays of a stub
   struct, then casts them to FILE*.  Provide buffers big enough for glibc's
   FILE and copy the real streams in before main. */
struct __sFstub __stdin[32], __stdout[32], __stderr[32];
#undef stderr
#undef stdout
#undef stdin
extern void *stderr, *stdout, *stdin;   /* glibc's FILE* globals */
__attribute__((constructor))
static void shim_stdio_init(void) {
    memcpy(__stderr, stderr, sizeof __stderr);
    memcpy(__stdout, stdout, sizeof __stdout);
    memcpy(__stdin, stdin, sizeof __stdin);
}
