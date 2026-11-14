#define F(...) f(__VA_ARGS__)
#define G(a, ...) g(a, __VA_ARGS__)
#define G2(a, ...) g(a __VA_ARGS__)
#define H(fmt, args...) printf(fmt, args)
#define I(fmt, ...) printf(fmt, ## __VA_ARGS__)
#define COUNT(...) ARG(__VA_ARGS__, 3, 2, 1, 0)
#define ARG(a, b, c, d, ...) d
#define STRALL(...) #__VA_ARGS__
#define SQ(x) ((x) * (x))
int a = F(1, 2, 3);
int b = F();
int c = G(1, 2, 3);
int d = G2(1,);
int e = H("x", 1, 2);
int f = I("x");
int g = I("x", 1, 2);
int h = COUNT(a, b);
int i = COUNT(a);
const char *s = STRALL(a, b,  c);
int j = F(SQ(2), SQ(3));
