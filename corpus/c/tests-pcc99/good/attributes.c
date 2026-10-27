int a __attribute__((unused));
struct __attribute__((packed)) s { char c; int i; };
typedef int myint __attribute__((aligned(4)));
void f(void) __attribute__((noreturn));
__attribute__((noinline)) static int g(int x) { return x; }
int h(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int (__attribute__((unused)) *fp)(void);
void k(int x __attribute__((unused))) { l: __attribute__((unused)) ; }
int * __attribute__((aligned(8))) pa;
