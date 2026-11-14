/* tokens only: the expanded text is not C, so the C99 grammar is not asked to read it */
%:define X 1
int a = X;
#define S(x) %:x
const char *b = S(hi);
#define C(a, b) a %:%: b
int C(x, y);
%:ifdef Z
int no;
%:else
int yes;
%:endif
#if 0
%:if 1
int skipped;
%:endif
#else
int taken;
#endif
#define Q(x) <:x:>
int c = Q(1);
int d<:2:> = <%1, 2%>;
#define STR(x) #x
const char *e = STR(<:);
const char *f = STR(%:);
