/* nb.c -- runtime/hbnf_scalar.h against fast_float (the library simdjson uses for doubles) and glibc's strtod, on the
 * numbers of four files (one number to a line); prints "SET LABEL NS_PER_NUMBER" lines: the best of REPS passes.  The
 * strings: hbnf_unescape against a byte loop, in GB/s.  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "hbnf_scalar.h"
int ff_parse_d (const char *s, unsigned long n, double *d);
int ff_parse_i (const char *s, unsigned long n, long long *v);
typedef struct { const char *p; size_t n; } tok;
static tok *load (const char *file, size_t *count)
{
    FILE *f = fopen (file, "rb"); long len; char *b; tok *t; size_t i, k = 0, st = 0;
    if (!f) { fprintf (stderr, "cannot read %s\n", file); exit (2); }
    fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET); b = (char *) malloc ((size_t) len + 1);
    if (fread (b, 1, (size_t) len, f) != (size_t) len) exit (2);
    b[len] = 0; fclose (f); t = (tok *) malloc (sizeof *t * ((size_t) len / 2 + 2));
    for (i = 0; i <= (size_t) len; i++) if (i == (size_t) len || b[i] == '\n') { t[k].p = b + st; t[k].n = i - st; k++; st = i + 1; }
    *count = k; return t;
}
static double now (void) { struct timespec a; clock_gettime (CLOCK_MONOTONIC, &a); return a.tv_sec * 1e9 + a.tv_nsec; }
static volatile double sink;
static void one (const char *set, const char *label, tok *t, size_t k, int which, int reps, int ints)
{
    double best = 1e18, acc = 0; int r; size_t i; char buf[64];
    for (r = 0; r < reps; r++) {
        double a = now (); acc = 0;
        for (i = 0; i < k; i++) {
            if (which == 0) { int64_t iv; double dv; acc += hbnf_parse_number (t[i].p, t[i].n, &iv, &dv) == 1 ? (double) iv : dv; }
            else if (which == 1) { if (ints) { long long v; ff_parse_i (t[i].p, t[i].n, &v); acc += (double) v; } else { double d; ff_parse_d (t[i].p, t[i].n, &d); acc += d; } }
            else { memcpy (buf, t[i].p, t[i].n); buf[t[i].n] = 0; acc += ints ? (double) strtoll (buf, 0, 10) : strtod (buf, 0); }
        }
        a = now () - a; if (a < best) best = a;
    }
    sink = acc; printf ("%s|%s|%.2f\n", set, label, best / (double) k);
}
int main (int argc, char **argv)
{
    static const char *sets[] = { "ints", "floats", "mid17", "rand17" };
    static const char *names[] = { "the document's integers (4.7 digits)", "the document's decimals (like 308.248)", "17-digit decimals, 1e-5 to 1e11", "17-digit doubles of every magnitude" };
    int s;
    (void) argc;
    for (s = 0; s < 4; s++) {
        char file[256]; size_t k; tok *t; int reps = s < 2 ? 300 : 40;
        snprintf (file, sizeof file, "%s/%s.txt", argv[1], sets[s]);
        t = load (file, &k);
        one (names[s], "hbnf_parse_number", t, k, 0, reps, s == 0);
        one (names[s], "fast_float", t, k, 1, reps, s == 0);
        one (names[s], "strtod", t, k, 2, reps, s == 0);
    }
    {
        static char src[1 << 16], dst[1 << 16]; size_t n, i; int dens, r;
        for (dens = 0; dens <= 2; dens++) {
            double bh = 1e18, bb = 1e18; size_t j;
            n = 0;
            while (n + 16 < sizeof src)
                for (j = 0; j < 64 && n + 16 < sizeof src; j++) {
                    src[n++] = 'a' + (char) (j % 26);
                    if (dens && j % (dens == 1 ? 32 : 8) == 5 && n + 16 < sizeof src) { src[n++] = '\\'; src[n++] = 'n'; }
                }
            for (r = 0; r < 300; r++) { double a = now (); (void) hbnf_unescape (src, n, dst); a = now () - a; if (a < bh) bh = a; }
            for (r = 0; r < 300; r++) {
                double a = now (); size_t o = 0;
                for (i = 0; i < n; i++) { char c = src[i]; if (c == '\\') { i++; c = src[i] == 'n' ? '\n' : src[i]; } dst[o++] = c; }
                a = now () - a; if (a < bb) bb = a;
            }
            printf ("unescape|%s|%.2f|%.2f\n", dens == 0 ? "a string with no escape" : dens == 1 ? "an escape in 32 bytes" : "an escape in 8 bytes", (double) n / bh, (double) n / bb);
        }
    }
    return 0;
}
