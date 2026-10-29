/* hbnf_scalar.h -- the two conversions a reader of a tape (runtime/hbnf_tape.h) needs after the parse: the text of
 * a JSON-like number as an integer or a double, and the text of a string as bytes.  A tape holds only where
 * the text lies; these read it, as fast as the best libraries do.
 *
 *   hbnf_parse_number (s, n, &i, &d)   1: an integer, in i      2: anything else, in d      0: not a number
 *   hbnf_has_escape (s, n)             does the string content hold a backslash (if not, it is its own bytes)
 *   hbnf_has_escape_in (s, n, avail)   the same where avail >= n bytes may be read from s (faster for short strings)
 *   hbnf_unescape (s, n, out)          the bytes of a string content, escapes undone; returns the length, or
 *                                      (size_t) -1 for a bad escape.  out has room for n bytes.
 *
 * Numbers: digits are taken eight at a time; an integer of up to 19 digits is read directly; a decimal
 * with up to 19 significant digits is a mantissa and an exponent, and the double is the exact product when
 * both are small (one multiplication or division), else the Eisel-Lemire algorithm (Lemire, "Number
 * Parsing at a Gigabyte per Second", 2021): one 64x64->128 multiplication by a table entry of
 * hbnf_pow5.h, and an answer correctly rounded in all but a few cases that it detects and hands to strtod,
 * as it does a number of more than 19 significant digits.  The result is the same as strtod's, bit for
 * bit; layouts/../tests/scalar.sh checks that on millions of numbers.
 * Strings: the content is scanned sixteen bytes at a time for a backslash (SSE2, or a byte loop), the runs
 * between escapes are copied, \uXXXX (and a surrogate pair) becomes UTF-8.  Little-endian x86 and
 * 64-bit unsigned __int128 assumed for the fast paths; others take the byte loops and strtod.  */
#ifndef HBNF_SCALAR_H
#define HBNF_SCALAR_H
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "hbnf_pow5.h"
#if defined(__SSE2__)
#include <emmintrin.h>
#endif

/* ---- numbers ---- */

static inline int hbnf_eight_digits (uint64_t v)       /* are all eight bytes of v ASCII digits? */
{
    return ((v & 0xF0F0F0F0F0F0F0F0ULL) | (((v + 0x0606060606060606ULL) & 0xF0F0F0F0F0F0F0F0ULL) >> 4))
           == 0x3333333333333333ULL;
}

static inline uint32_t hbnf_parse_eight (uint64_t v)    /* the number the eight digits make (little-endian load) */
{
    const uint64_t mask = 0x000000FF000000FFULL, mul1 = 0x000F424000000064ULL, mul2 = 0x0000271000000001ULL;
    v -= 0x3030303030303030ULL;
    v = (v * 10) + (v >> 8);
    v = (((v & mask) * mul1) + (((v >> 16) & mask) * mul2)) >> 32;
    return (uint32_t) v;
}

/* w * 10^q as the double nearest to it; 1 when decided, 0 when only strtod can say */
static inline int hbnf_eisel_lemire (int64_t q, uint64_t w, double *out)
{
    unsigned __int128 pr;
    uint64_t lo, hi, mant, bits;
    int lz, upper;
    int64_t power2;
    if (w == 0 || q < HBNF_POW5_MIN) { *out = 0.0; return 1; }
    if (q > HBNF_POW5_MAX) { *out = INFINITY; return 1; }
    lz = __builtin_clzll (w);
    w <<= lz;
    {
        const uint64_t *t = &hbnf_pow5[2 * (q - HBNF_POW5_MIN)];
        pr = (unsigned __int128) w * t[0];
        lo = (uint64_t) pr;
        hi = (uint64_t) (pr >> 64);
        if ((hi & 0x1FF) == 0x1FF) {                    /* the high word may still change: add the low word's carry */
            unsigned __int128 pr2 = (unsigned __int128) w * t[1];
            lo += (uint64_t) (pr2 >> 64);
            if ((uint64_t) (pr2 >> 64) > lo) hi++;
        }
    }
    if (lo == 0xFFFFFFFFFFFFFFFFULL && (q < -27 || q > 55)) return 0;      /* too close to call */
    upper = (int) (hi >> 63);
    mant = hi >> (upper + 9);
    power2 = (((152170 + 65536) * q) >> 16) + 63 + upper - lz + 1023;
    if (power2 <= 0) {                                   /* a subnormal, or a zero */
        if (-power2 + 1 >= 64) { *out = 0.0; return 1; }
        mant >>= -power2 + 1;
        mant += (mant & 1);
        mant >>= 1;
        power2 = (mant < (1ULL << 52)) ? 0 : 1;
    } else {
        if (lo <= 1 && q >= -4 && q <= 23 && (mant & 3) == 1) {          /* may be exactly between two doubles */
            if ((mant << (upper + 64 - 52 - 3)) == hi) mant &= ~1ULL;
        }
        mant += (mant & 1);
        mant >>= 1;
        if (mant >= (2ULL << 52)) { mant = 1ULL << 52; power2++; }
        if (power2 >= 0x7FF) { *out = INFINITY; return 1; }
    }
    bits = (mant & ((1ULL << 52) - 1)) | ((uint64_t) power2 << 52);
    memcpy (out, &bits, 8);
    return 1;
}

static const double hbnf_p10[23] = {1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
                                    1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22};

static __attribute__ ((noinline, unused)) double hbnf_strtod_slow (const char *s, size_t n)
{
    char stack[256], *b = n < sizeof stack ? stack : (char *) malloc (n + 1);
    double d;
    memcpy (b, s, n);
    b[n] = 0;
    d = strtod (b, 0);
    if (b != stack) free (b);
    return d;
}

/* the number of ASCII digits at p, eight at a time */
static inline size_t hbnf_digit_run (const char *p, const char *end)
{
    const char *q = p;
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    while (q + 8 <= end) {
        uint64_t w;
        memcpy (&w, q, 8);
        if (!hbnf_eight_digits (w)) break;
        q += 8;
    }
#endif
    while (q < end && (unsigned) (*q - '0') < 10) q++;
    return (size_t) (q - p);
}

/* m * 10^k + the k digits at p (all known to be digits); k small enough that the result fits */
static inline uint64_t hbnf_accumulate (uint64_t m, const char *p, size_t k)
{
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    while (k >= 8) {
        uint64_t w;
        memcpy (&w, p, 8);
        m = m * 100000000ULL + hbnf_parse_eight (w);
        p += 8;
        k -= 8;
    }
#endif
    while (k--) m = m * 10 + (uint64_t) (*p++ - '0');
    return m;
}

/* The text of a number (-?digits[.digits][(e|E)[+-]digits], already checked by the grammar, but tolerated
   if wrong: 0) as an integer (1, in *iv) when it has no fraction and no exponent and fits an int64, else as
   a double (2, in *dv). */
static inline int hbnf_parse_number (const char *s, size_t n, int64_t *iv, double *dv)
{
    const char *p = s, *end = s + n, *ip, *fp = 0;
    size_t il, fl = 0, zf = 0, sd;
    int neg = 0, hasexp = 0;
    int64_t e = 0;
    uint64_t m;
    double d;
    if (p < end && *p == '-') { neg = 1; p++; }
    ip = p;
    il = hbnf_digit_run (p, end);
    if (il == 0) return 0;
    p += il;
    if (p < end && *p == '.') {
        p++;
        fp = p;
        fl = hbnf_digit_run (p, end);
        if (fl == 0) return 0;
        p += fl;
    }
    if (p < end && (*p == 'e' || *p == 'E')) {
        size_t el;
        int es = 1;
        hasexp = 1;
        p++;
        if (p < end && (*p == '+' || *p == '-')) { es = *p == '-' ? -1 : 1; p++; }
        el = hbnf_digit_run (p, end);
        if (el == 0) return 0;
        e = el > 6 ? 999999 : (int64_t) hbnf_accumulate (0, p, el);       /* so large it is 0 or infinity anyway */
        e *= es;
        p += el;
    }
    if (p != end) return 0;
    while (il > 1 && *ip == '0') { ip++; il--; }                          /* leading zeros */
    if (fl == 0 && !hasexp) {                                             /* an integer */
        if (il <= 18) {
            m = hbnf_accumulate (0, ip, il);
            *iv = neg ? -(int64_t) m : (int64_t) m;
            return 1;
        }
        if (il == 19) {
            m = hbnf_accumulate (0, ip, il);
            if (neg ? m <= 9223372036854775808ULL : m <= 9223372036854775807ULL) {
                *iv = neg ? (int64_t) (0 - m) : (int64_t) m;
                return 1;
            }
            d = (double) m;
            *dv = neg ? -d : d;
            return 2;
        }
        goto slow;                                                        /* more than 19 digits */
    }
    /* a decimal: the significant digits of the integer part and the fraction make the mantissa */
    if (il == 1 && *ip == '0') {                                          /* 0.000123: the fraction's leading zeros do not count */
        while (zf < fl && fp[zf] == '0') zf++;
        sd = fl - zf;
        if (sd == 0) { *dv = neg ? -0.0 : 0.0; return 2; }
        m = hbnf_accumulate (0, fp + zf, sd);
    } else {
        sd = il + fl;
        if (sd > 19) goto slow;
        m = hbnf_accumulate (0, ip, il);
        if (fl) m = hbnf_accumulate (m, fp, fl);
    }
    if (sd > 19) goto slow;
    e -= (int64_t) fl;
    if (m < (1ULL << 53) && e >= -22 && e <= 22) {                        /* one exact operation */
        d = (double) m;
        d = e < 0 ? d / hbnf_p10[-e] : d * hbnf_p10[e];
    } else if (!hbnf_eisel_lemire (e, m, &d)) {
        goto slow;
    }
    *dv = neg ? -d : d;
    return 2;
slow:
    d = hbnf_strtod_slow (s, n);
    *dv = d;
    return 2;
}

/* ---- strings ---- */

/* the index of the first backslash in s[i..n), or n */
static inline size_t hbnf_find_backslash (const char *s, size_t i, size_t n)
{
#if defined(__SSE2__)
    const __m128i bs = _mm_set1_epi8 ('\\');
    while (i + 16 <= n) {
        unsigned mask = (unsigned) _mm_movemask_epi8 (_mm_cmpeq_epi8 (_mm_loadu_si128 ((const __m128i *) (s + i)), bs));
        if (mask) return i + (size_t) __builtin_ctz (mask);
        i += 16;
    }
#endif
    while (i < n && s[i] != '\\') i++;
    return i;
}

static inline int hbnf_has_escape (const char *s, size_t n)
{
    return hbnf_find_backslash (s, 0, n) < n;
}

/* The same, for a string that has more input after it: avail >= n is how many bytes may be read from s.  With 16
   or more, the last part is one masked 16-byte load and not a byte loop, which is what most strings, being
   shorter than 16, would otherwise cost.  Nothing past s + avail is read. */
static inline int hbnf_has_escape_in (const char *s, size_t n, size_t avail)
{
#if defined(__SSE2__)
    const __m128i bs = _mm_set1_epi8 ('\\');
    size_t i = 0;
    for (; i + 16 <= n; i += 16)
        if (_mm_movemask_epi8 (_mm_cmpeq_epi8 (_mm_loadu_si128 ((const __m128i *) (s + i)), bs))) return 1;
    if (i == n) return 0;
    if (i + 16 <= avail) {
        unsigned m = (unsigned) _mm_movemask_epi8 (_mm_cmpeq_epi8 (_mm_loadu_si128 ((const __m128i *) (s + i)), bs));
        return (m & ((1u << (n - i)) - 1)) != 0;
    }
    for (; i < n; i++) if (s[i] == '\\') return 1;
    return 0;
#else
    (void) avail;
    return hbnf_has_escape (s, n);
#endif
}

static inline int hbnf_hex_value (char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if ((c | 32) >= 'a' && (c | 32) <= 'f') return (c | 32) - 'a' + 10;
    return -1;
}

static inline int hbnf_hex4 (const char *p, uint32_t *u)
{
    int a = hbnf_hex_value (p[0]), b = hbnf_hex_value (p[1]), c = hbnf_hex_value (p[2]), d = hbnf_hex_value (p[3]);
    if ((a | b | c | d) < 0) return 0;
    *u = (uint32_t) ((a << 12) | (b << 8) | (c << 4) | d);
    return 1;
}

static inline size_t hbnf_put_utf8 (uint32_t u, char *out)
{
    if (u < 0x80) { out[0] = (char) u; return 1; }
    if (u < 0x800) { out[0] = (char) (0xC0 | (u >> 6)); out[1] = (char) (0x80 | (u & 63)); return 2; }
    if (u < 0x10000) {
        out[0] = (char) (0xE0 | (u >> 12)); out[1] = (char) (0x80 | ((u >> 6) & 63)); out[2] = (char) (0x80 | (u & 63));
        return 3;
    }
    out[0] = (char) (0xF0 | (u >> 18)); out[1] = (char) (0x80 | ((u >> 12) & 63));
    out[2] = (char) (0x80 | ((u >> 6) & 63)); out[3] = (char) (0x80 | (u & 63));
    return 4;
}

/* The content of a string (without its quotes) with the escapes undone, in out (n bytes are enough);
   the length, or (size_t) -1 when an escape is wrong: an unknown one, a bad \u, or a lone surrogate. */
static inline size_t hbnf_unescape (const char *s, size_t n, char *out)
{
    size_t i = 0, o = 0;
    while (i < n) {
        size_t j = hbnf_find_backslash (s, i, n);
        if (j > i) { memcpy (out + o, s + i, j - i); o += j - i; i = j; }
        if (i >= n) break;
        if (++i >= n) return (size_t) -1;
        switch (s[i++]) {
        case '"': out[o++] = '"'; break;
        case '\\': out[o++] = '\\'; break;
        case '/': out[o++] = '/'; break;
        case 'b': out[o++] = '\b'; break;
        case 'f': out[o++] = '\f'; break;
        case 'n': out[o++] = '\n'; break;
        case 'r': out[o++] = '\r'; break;
        case 't': out[o++] = '\t'; break;
        case 'u': {
            uint32_t u, lo;
            if (i + 4 > n || !hbnf_hex4 (s + i, &u)) return (size_t) -1;
            i += 4;
            if (u >= 0xD800 && u < 0xDC00) {                      /* a high surrogate wants a low one next */
                if (i + 6 > n || s[i] != '\\' || s[i + 1] != 'u' || !hbnf_hex4 (s + i + 2, &lo) || lo < 0xDC00 || lo > 0xDFFF)
                    return (size_t) -1;
                u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
                i += 6;
            } else if (u >= 0xDC00 && u <= 0xDFFF) {
                return (size_t) -1;
            }
            o += hbnf_put_utf8 (u, out + o);
            break;
        }
        default: return (size_t) -1;
        }
    }
    return o;
}
#endif
