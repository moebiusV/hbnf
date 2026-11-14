#define F(x, ...) f(x __VA_OPT__(,) __VA_ARGS__)
#define G(a, ...) g(a __VA_OPT__(, #__VA_ARGS__))
#define H(a, ...) a ## __VA_OPT__(_v)
#define E(...) __VA_OPT__(a +) c
#define EM
#define K(...) k(__VA_OPT__(x))
int a = F(1); int b = F(1, 2); int c = F(1,);
int d = G(1); int e = G(1, x y);
int H(x); int H(y, 1);
int f = E(); int g = E(1);
int h = K(EM); int i = K(); int j = K(1);
