#define N 10
#define M (N + 1)
#define EMPTY
#define S "N is not expanded here"
int a = N, b = M, c = N*M;
char *s = S; /* N and M in a comment */ // N again
char d = 'N';
EMPTY int e;
#define N 20
int f = N + M;
#undef N
int g = N;
#define A B
#define B C
#define C 42
int h = A;
