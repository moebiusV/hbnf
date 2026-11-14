#define CAT(a, b) a ## b
#define XCAT(a, b) CAT(a, b)
#define N 7
int CAT(x, y) = CAT(1, 2);
int XCAT(v, N) = 3;
int CAT(a, N) = 4;
#define PRE(x) pre_ ## x ## _post
int PRE(mid);
#define EMPTYCAT(a, b) f(a ## b)
int e1 = EMPTYCAT(, b);
int e2 = EMPTYCAT(a, );
int e3 = EMPTYCAT(, );
#define OP(a) a ## =
int k = 1;
void fn(void) { k OP(+) 2; }
#define NUM(a) a ## 0
int n = NUM(1) + NUM(2);
#define OBJ ab ## cd
int o = OBJ;
