/* Shims so OpenBSD ntpd links and runs on glibc/Linux for the `ntpd -n`
 * (configtest) proof.  Three kinds: (a) OpenBSD libc-internal names glibc
 * spells differently (__errno, __isfinite, __stderr/__stdout/__stdin),
 * (b) OpenBSD syscalls that don't exist on Linux (pledge/unveil/sysctl/
 * setproctitle/adjfreq), and (c) runtime features `-n` never reaches
 * (TLS constraints, MD5 auth, resolver), stubbed to fail cleanly.  imsg is
 * the one real library, compiled from lib/libutil. */

#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/sysctl.h>
#include <md5.h>
#include <tls.h>
#include <resolv.h>

extern int *__errno_location(void);

/* --- OpenBSD syscalls (no-ops / "unsupported") --- */
int pledge(const char *p, const char *e) { (void)p; (void)e; return 0; }
int unveil(const char *p, const char *perm) { (void)p; (void)perm; return 0; }
void setproctitle(const char *fmt, ...) { (void)fmt; }
int sysctl(const int *name, unsigned int namelen, void *oldp, size_t *oldlenp,
           void *newp, size_t newlen) {
    (void)name; (void)namelen; (void)oldp; (void)oldlenp; (void)newp; (void)newlen;
    return -1;
}
int adjfreq(const int64_t *freq, int64_t *oldfreq) {
    if (oldfreq) *oldfreq = 0;
    (void)freq;
    return 0;
}

/* --- libc-internal names --- */
int *__errno(void) { return __errno_location(); }
int __isfinite(double x) { return __builtin_isfinite(x); }
int __isfinitef(float x) { return __builtin_isfinite(x); }
int __isfinitel(long double x) { return __builtin_isfinite(x); }

/* OpenBSD stdio spells stdin/stdout/stderr as __stdin/... arrays of a stub
 * struct, then casts them to FILE*.  Provide buffers big enough for glibc's
 * FILE and copy the real streams in before main. */
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

/* --- resolver (not reached under -n) --- */
int res_init(void) { return 0; }
struct __res_state _res;

/* --- MD5 (NTP packet auth; not reached under -n) --- */
void MD5Init(MD5_CTX *c) { (void)c; }
void MD5Update(MD5_CTX *c, const u_int8_t *d, size_t n) { (void)c; (void)d; (void)n; }
void MD5Final(u_int8_t out[MD5_DIGEST_LENGTH], MD5_CTX *c) { (void)out; (void)c; }

/* --- libtls (constraints' HTTPS; not reached under -n) --- */
const char *tls_error(struct tls *c) { (void)c; return "tls unavailable"; }
struct tls_config *tls_config_new(void) { return NULL; }
void tls_config_free(struct tls_config *c) { (void)c; }
const char *tls_default_ca_cert_file(void) { return ""; }
int tls_config_set_ca_mem(struct tls_config *c, const uint8_t *ca, size_t len) {
    (void)c; (void)ca; (void)len; return -1;
}
void tls_config_insecure_noverifytime(struct tls_config *c) { (void)c; }
struct tls *tls_client(void) { return NULL; }
int tls_configure(struct tls *c, struct tls_config *cfg) { (void)c; (void)cfg; return -1; }
void tls_free(struct tls *c) { (void)c; }
int tls_connect_servername(struct tls *c, const char *host, const char *port,
                           const char *servername) {
    (void)c; (void)host; (void)port; (void)servername; return -1;
}
ssize_t tls_read(struct tls *c, void *buf, size_t len) {
    (void)c; (void)buf; (void)len; return -1;
}
ssize_t tls_write(struct tls *c, const void *buf, size_t len) {
    (void)c; (void)buf; (void)len; return -1;
}
int tls_close(struct tls *c) { (void)c; return -1; }
time_t tls_peer_cert_notbefore(struct tls *c) { (void)c; return 0; }
time_t tls_peer_cert_notafter(struct tls *c) { (void)c; return 0; }
uint8_t *tls_load_file(const char *file, size_t *len, char *password) {
    (void)file; (void)password; if (len) *len = 0; return NULL;
}

/* freezero — OpenBSD's explicit_bzero+free.  glibc has explicit_bzero. */
void freezero(void *ptr, size_t len) {
    if (ptr) {
        volatile unsigned char *p = ptr;
        while (len--) *p++ = 0;
        free(ptr);
    }
}
