/* no rewind: #line numbers places in the text the user wrote, and a rewind starts over on text that is not */
int a = __COUNTER__, b = __COUNTER__;
#define C __COUNTER__
int c = C, d = C;
#line 100
int e = __LINE__;
#line 200 "other.c"
int f = __LINE__; const char *g = __FILE__;
int h = __LINE__;
#define LINE_OF(x) (x + __LINE__)
int i = LINE_OF(7);
int k = __STDC__, m = __STDC_HOSTED__;
#if __STDC_VERSION__ >= 199901L
int std99;
#endif
void fn(void) {
_Pragma("omp parallel") int p;
}
#define P(x) _Pragma(#x) int q;
P(foo bar)
#ifdef __COUNTER__
int has_counter;
#endif
#if defined(__LINE__) && defined(__FILE__) && defined __DATE__ && defined(__TIME__) && !defined(__NOT_THERE__)
int has_line;
#endif
#undef __STDC_HOSTED__
#ifndef __STDC_HOSTED__
int unhosted;
#endif
