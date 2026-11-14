/* tokens only: the expanded text is not C, so the C99 grammar is not asked to read it */
/* two tokens that a macro puts side by side are not one token (6.10.3.3, 6.10.3.4): the output has them apart */
#define M -
int a = -M 1;
int b = M-1;
#define P +
int c = P+ 1;
#define NEG(x) -x
int d = NEG(-1);
int e = NEG(NEG(1));
#define AMP &
int f = AMP&1;
#define LT <
int g = LT< 2;
#define DOT .
int h = DOT.5;
#define ID(x) x
int i = ID(-)-1;
int j = ID(+)+ID(+)1;
#define EMPTY
int k = -EMPTY-1;
int l = +EMPTY+1;
#define X x
int m = X X;
int n = ID(a)ID(b);
