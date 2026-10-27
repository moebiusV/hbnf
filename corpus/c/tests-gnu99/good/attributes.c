int a __attribute__((unused));
int b __attribute__((aligned(8), packed)) = 1;
struct __attribute__((packed)) s { char c; int i; };
struct t { char c; int i; } __attribute__((packed));
enum __attribute__((packed)) e { A, B };
typedef int myint __attribute__((aligned(4)));
void f(void) __attribute__((noreturn));
__attribute__((noinline)) static int g(int x) { return x; }
int h(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
char *p __attribute__((mode(__word__)));
int (__attribute__((unused)) *fp)(void);
void k(int x __attribute__((unused))) { l: __attribute__((unused)) ; }
extern int ext __attribute__((__weak__)), ext2 __attribute__ ((alias ("ext")));
