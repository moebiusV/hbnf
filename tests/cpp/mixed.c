#define DEBUG
#define LOG(x) ((void)(x))
#define EMPTY_ARG(x) (x 0)
#ifdef DEBUG
#define CHECK(c) LOG(c)
#else
#define CHECK(c) 0
#endif
void f(void) { CHECK(1); }
int g = EMPTY_ARG();
#define PTR(T) T *
PTR(int) p;
#define F(x) x
#define G F(1)
int h = G + F(F(2));
struct s { int n; } v = { 1 };
