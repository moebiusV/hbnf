/* tokens only: the expanded text is not C, so the C99 grammar is not asked to read it */
/* where a # is a directive (C11 6.10 p2): the first token of a line, after blanks and comments, in the text as written */
int a = 3 # 4;
int b = 5 ## 6;
#define S(x) #x
int c = 1 + S(2);
  #  define Z 7
int d = Z;
#define EMPTY
EMPTY # define X 1
int e = X;
#define H # define Y 1
H
int f = Y;
/* c */ # define W1 1
int g = W1;
# /* c */ define W2 2
int h = W2;
/* a
   b */ #define W3 3
int i = W3;
#define W4 /* a
  b */ 4
int j = W4;
#if 1 /* c */
int k;
#endif // x
#
int l;
#if 1
#define IN 5
#endif
int m = IN;
#define STR "/*"
const char *n = STR; /* x */ int o;
#define Q "a\"b"
const char *p = Q;
#define CH '"'
char q = CH; /* y */
	#	define TAB 6
int r = TAB;
