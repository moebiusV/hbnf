/* runtime/hbnf_scalar.h against the C library: every number must come out as strtod (or strtoll) says, bit for
   bit, and every string as a plain byte loop unescapes it.  Prints "scalar: OK (...)" or the first failures. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "hbnf_scalar.h"

static int bad;
static unsigned long checked;
static uint64_t rs = 88172645463325252ULL;
static uint64_t rnd (void) { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }
static uint64_t bits (double d) { uint64_t b; memcpy (&b, &d, 8); return b; }
#define FAIL(...) do { if (bad++ < 8) { printf ("FAIL: " __VA_ARGS__); printf ("\n"); } } while (0)

static void num (const char *str)
{
    int64_t iv = 0; double dv = 0, ref;
    char *endp;
    int k = hbnf_parse_number (str, strlen (str), &iv, &dv);
    checked++;
    ref = strtod (str, &endp);
    if (*endp) { FAIL ("the test gave strtod a bad number: %s", str); return; }
    if (k == 1) {
        long long r = strtoll (str, &endp, 10);
        if (*endp || r != iv) FAIL ("%s: integer %" PRId64 ", strtoll %lld", str, iv, r);
    } else if (k == 2) {
        if (bits (dv) != bits (ref)) FAIL ("%s: %.17g (%016" PRIx64 ") but strtod %.17g (%016" PRIx64 ")", str, dv, bits (dv), ref, bits (ref));
    } else {
        FAIL ("%s: refused", str);
    }
}

static void edge_numbers (void)
{
    static const char *t[] = {
        "0", "-0", "1", "-1", "00012", "0.0", "-0.0", "0e0", "1e0", "1E5", "1e+5", "1e-5", "0.1", "0.5", "123.456",
        "999999999999999999", "1000000000000000000", "9223372036854775807", "-9223372036854775808", "9223372036854775808",
        "-9223372036854775809", "18446744073709551615", "18446744073709551616", "12345678901234567890",
        "1.7976931348623157e308", "1.7976931348623159e308", "1.8e308", "2.2250738585072014e-308", "2.2250738585072011e-308",
        "4.9406564584124654e-324", "2.4703282292062327e-324", "2.4703282292062328e-324", "1e-400", "1e400", "1e-1000000",
        "1e1000000", "0.000000000000000000001", "0.30000000000000004", "9007199254740993", "9007199254740993e0",
        "9007199254740992.5", "4503599627370497.5", "1.00000000000000011102230246251565404236316680908203125",
        "5e-324", "3e-324", "2.5e-324", "1e23", "8.5e-5", "123456789012345678e5", "0.1234567890123456789",
        "0.12345678901234567890123", "100000000000000000000", "1.5", "2.5e2", "-17.25e-3", 0 };
    int i;
    for (i = 0; t[i]; i++) num (t[i]);
}

static void random_doubles (long count)
{
    long i;
    char b[64];
    for (i = 0; i < count; i++) {
        double d; int w;
        uint64_t x = rnd ();
        memcpy (&d, &x, 8);
        if (d != d || d - d != 0) continue;                      /* not NaN or infinity */
        for (w = 15; w <= 17; w++) {                              /* the shortest of 15, 16, 17 digits that returns d */
            snprintf (b, sizeof b, "%.*g", w, d);
            if (strtod (b, 0) == d || w == 17) break;
        }
        num (b);
        snprintf (b, sizeof b, "%.*e", (int) (rnd () % 18), d);   /* and fewer digits, rounded */
        num (b);
    }
}

static void random_decimals (long count)
{
    long i;
    char b[96];
    for (i = 0; i < count; i++) {
        int nd = 1 + (int) (rnd () % 19), dot = (int) (rnd () % (nd + 2)), k, o = 0;
        long e = (long) (rnd () % 700) - 360;
        if (rnd () & 1) b[o++] = '-';
        b[o++] = (char) ('1' + rnd () % 9);
        for (k = 1; k < nd; k++) { if (k == dot) b[o++] = '.'; b[o++] = (char) ('0' + rnd () % 10); }
        if (dot == nd && nd > 1) { b[o++] = '.'; b[o++] = '0'; }
        if (rnd () % 4) o += sprintf (b + o, "e%ld", e);
        b[o] = 0;
        num (b);
    }
}

static void grid (void)
{
    char b[64];
    int m, e;
    for (m = 1; m <= 2500; m++)
        for (e = -360; e <= 320; e++) { snprintf (b, sizeof b, "%de%d", m, e); num (b); }
}

static void halfway (void)
{
    char b[64];
    long i;
    for (i = 0; i < 300000; i++) {
        uint64_t n = (1ULL << 53) + (rnd () % (UINT64_MAX - (1ULL << 53) + 1));     /* integers between 2^53 and 2^64 */
        snprintf (b, sizeof b, "%" PRIu64 "e0", n); num (b);
        snprintf (b, sizeof b, "%" PRIu64 ".0", n); num (b);
        snprintf (b, sizeof b, "%" PRIu64, n >> 1); num (b);
        n = (1ULL << 52) + (rnd () % (1ULL << 52));                                /* x.5, x.25, x.75: ties and near ties */
        snprintf (b, sizeof b, "%" PRIu64 ".5", n); num (b);
        snprintf (b, sizeof b, "%" PRIu64 ".25", n); num (b);
        snprintf (b, sizeof b, "%" PRIu64 ".75", n); num (b);
        n = (rnd () % (1ULL << 50)) + 1;
        snprintf (b, sizeof b, "%" PRIu64 "e%d", n, (int) (rnd () % 60) - 30); num (b);
    }
}

/* ---- strings: a byte loop is the reference ---- */
static long ref_unescape (const unsigned char *s, size_t n, unsigned char *out)
{
    size_t i = 0, o = 0;
    while (i < n) {
        if (s[i] != '\\') { out[o++] = s[i++]; continue; }
        i++;
        if (i >= n) return -1;
        switch (s[i]) {
        case '"': out[o++] = '"'; i++; break;   case '\\': out[o++] = '\\'; i++; break;  case '/': out[o++] = '/'; i++; break;
        case 'b': out[o++] = 8; i++; break;     case 'f': out[o++] = 12; i++; break;     case 'n': out[o++] = 10; i++; break;
        case 'r': out[o++] = 13; i++; break;    case 't': out[o++] = 9; i++; break;
        case 'u': {
            unsigned u = 0, lo = 0; int k;
            if (i + 4 >= n) return -1;                                  /* four hex digits must follow the u */
            for (k = 1; k <= 4; k++) {
                int c = i + k < n ? s[i + k] : 0, v = c >= '0' && c <= '9' ? c - '0' : (c | 32) >= 'a' && (c | 32) <= 'f' ? (c | 32) - 'a' + 10 : -1;
                if (v < 0) return -1;
                u = u * 16 + (unsigned) v;
            }
            i += 5;
            if (u >= 0xD800 && u <= 0xDBFF) {
                if (i + 6 > n || s[i] != '\\' || s[i + 1] != 'u') return -1;
                for (k = 2; k <= 5; k++) {
                    int c = s[i + k], v = c >= '0' && c <= '9' ? c - '0' : (c | 32) >= 'a' && (c | 32) <= 'f' ? (c | 32) - 'a' + 10 : -1;
                    if (v < 0) return -1;
                    lo = lo * 16 + (unsigned) v;
                }
                if (lo < 0xDC00 || lo > 0xDFFF) return -1;
                u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
                i += 6;
            } else if (u >= 0xDC00 && u <= 0xDFFF) return -1;
            if (u < 0x80) out[o++] = (unsigned char) u;
            else if (u < 0x800) { out[o++] = (unsigned char) (0xC0 | u >> 6); out[o++] = (unsigned char) (0x80 | (u & 63)); }
            else if (u < 0x10000) { out[o++] = (unsigned char) (0xE0 | u >> 12); out[o++] = (unsigned char) (0x80 | ((u >> 6) & 63)); out[o++] = (unsigned char) (0x80 | (u & 63)); }
            else { out[o++] = (unsigned char) (0xF0 | u >> 18); out[o++] = (unsigned char) (0x80 | ((u >> 12) & 63)); out[o++] = (unsigned char) (0x80 | ((u >> 6) & 63)); out[o++] = (unsigned char) (0x80 | (u & 63)); }
            break;
        }
        default: return -1;
        }
    }
    return (long) o;
}

static void strings (long count)
{
    static const char *pieces[] = { "\\n", "\\t", "\\\"", "\\\\", "\\/", "\\b", "\\f", "\\r", "\\u0041", "\\u00e9", "\\u20AC",
                                    "\\ud83d\\ude00", "\\uD834\\uDD1E", "abc", "hello world", "0123456789abcdef0123456789abcdef", "\xc3\xa9", "" };
    static const char *wrong[] = { "\\x", "\\u12", "\\uzzzz", "\\ud800", "\\udc00", "\\ud800\\u0041", "\\", "\\ud83d\\ude0", "\\u" };
    long i;
    for (i = 0; i < count; i++) {
        char s[400]; unsigned char a[400], b[400]; size_t n = 0; int pc = (int) (rnd () % 12), k; long r; size_t g;
        for (k = 0; k < pc; k++) {
            const char *p = (rnd () % 40 == 0) ? wrong[rnd () % 9] : pieces[rnd () % 18];
            size_t l = strlen (p);
            if (n + l >= 300) break;
            memcpy (s + n, p, l); n += l;
            if (rnd () % 3 == 0) { size_t run = rnd () % 40; while (run-- && n < 300) s[n++] = (char) ('a' + rnd () % 26); }
        }
        s[n] = 0;
        r = ref_unescape ((unsigned char *) s, n, a);
        g = hbnf_unescape (s, n, (char *) b);
        checked++;
        if (r < 0 ? g != (size_t) -1 : (g != (size_t) r || memcmp (a, b, g))) FAIL ("unescape of \"%s\": reference %ld, ours %ld", s, r, (long) g);
        if (hbnf_has_escape (s, n) != (memchr (s, '\\', n) != 0)) FAIL ("has_escape of \"%s\"", s);
    }
}

/* hbnf_has_escape_in reads nothing past the bytes it is told it may: the strings sit at the end of exact-size
   buffers (the address sanitizer, when it is on, would stop an overread) and every length and slack is tried */
static void has_escape_in (void)
{
    size_t n, slack, k;
    for (n = 0; n <= 40; n++)
        for (slack = 0; slack <= 20; slack++)
            for (k = 0; k < 40; k++) {
                size_t total = n + slack, i;
                char *b = (char *) malloc (total ? total : 1);
                int want = 0;
                for (i = 0; i < total; i++) b[i] = (rnd () % 9 == 0 && (k & 1)) ? '\\' : (char) ('a' + rnd () % 26);
                for (i = 0; i < n; i++) if (b[i] == '\\') want = 1;
                checked++;
                if (hbnf_has_escape_in (b, n, total) != want) FAIL ("has_escape_in n=%zu slack=%zu: wrong", n, slack);
                free (b);
            }
}

int main (void)
{
    has_escape_in ();
    edge_numbers ();
    random_doubles (1500000);
    random_decimals (3000000);
    grid ();
    halfway ();
    strings (400000);
    if (bad) { printf ("scalar: %d FAILED of %lu\n", bad, checked); return 1; }
    printf ("scalar: OK (%lu numbers and strings agree with strtod and a byte loop)\n", checked);
    return 0;
}
