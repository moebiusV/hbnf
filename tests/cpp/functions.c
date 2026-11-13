#define SQ(x) ((x) * (x))
#define ADD(a, b) ((a) + (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define ZERO() 0
#define CALL(f, x) f(x)
int a = SQ(3), b = ADD(1, 2), c = MAX(a, b), d = ZERO();
int e = SQ(ADD(1, 2));
int f = ADD(SQ(2), (3, 4));
int g = SQ
  (5);
int h = ADD("a,b", ',');
int i = CALL(SQ, 4);
int SQ_not_a_call = 1;
int j = ADD(
    1,
    2);
