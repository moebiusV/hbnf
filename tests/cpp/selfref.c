#define if x(a); if
#define foo foo + 1
#define a b
#define b a
#define f(x) x + f(x)
#define g(x) f(g(x))
#define EMPTY
#define K K + K
int z = foo;
int q = a;
int r = b;
int s = f(1);
int t = f(f(2));
int u = g(3);
int w = K;
void h(void) { if (1) ; }
