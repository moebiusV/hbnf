#define L __LINE__
#define F(x) x + __LINE__
#define G(x) x
#define S(x) #x
int a = L;
int b = F(1);
int c = G(__LINE__);
int d = F(__LINE__), e = __LINE__;
int f = F(F(2));
const char *g = S(__LINE__);
/* a comment
   over two lines */
int h = L;
int i = G(
  1);
int j = __LINE__;
#if __LINE__ == 17
int k = 1;
#endif
