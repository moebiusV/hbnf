/* tokens only: the expanded text is not C, so the C99 grammar is not asked to read it */
#define a b\
c
int x = a;
in\
t y = 1;
int z = __LINE__;
int w = 1 \
 + 2;
int v = __LINE__;
#define M(a, \
   b) a + \
 b
int u = M(1,\
 2); int t = __LINE__;
char *s = "ab\
cd";
// a comment \
 continued
int r;
#define LONG 1 \
  + 2 \
  + 3
int q = LONG;
int p = __LINE__;
