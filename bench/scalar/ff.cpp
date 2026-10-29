// fast_float behind two C functions, so that the C benchmark can call it
#include "fast_float.h"
extern "C" int ff_parse_d (const char *s, unsigned long n, double *d) { auto r = fast_float::from_chars (s, s + n, *d); return r.ec == std::errc (); }
extern "C" int ff_parse_i (const char *s, unsigned long n, long long *v) { auto r = fast_float::from_chars (s, s + n, *v); return r.ec == std::errc (); }
