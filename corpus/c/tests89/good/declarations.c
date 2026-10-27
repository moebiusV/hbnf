/* storage classes, qualifiers, declarators, abstract declarators */
extern int e;
static const int c = 3;
volatile unsigned long ul;
char *argv[10];
int (*fp)(void);
int (*(*pfp)(int))[3];
int matrix[3][4];
const char *const names[] = { "a", "b", 0 };
unsigned u1 = 10u, u2 = 07ul, u3 = 0x1fUL;
double d = 1.5e3, d2 = .5, d3 = 2., d4 = 1e-3;
float f = 1.0f;
long double ld = 1.0L;
char ch = 'x', nl = '\n', wide = L'w';
char *s = "abc" "def";
char s2[] = "text";
int sizes[] = { sizeof(int), sizeof(char *), sizeof(sizes[0]) };
int g(void)
{
    register int r = 0;
    return (int)sizeof(int (*)(int)) + r;
}
