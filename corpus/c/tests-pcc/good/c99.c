struct p { int x, y; };
struct flex { int n; char data[]; };
enum e { A, B, };
inline static int sq(int x) { return x * x; }
void f(int n, int a[restrict static 4], int m[*], int p[const 3]);
int g(int n)
{
    int t = 0;
    t += n;
    int u = t;
    for (int i = 0; i < n; i++) u += i;
    struct p q = { .y = 2, .x = 1 };
    int arr[6] = { [4] = 5, [1] = 2, 3 };
    struct p *pp = &(struct p){ .x = 1 };
    int *ip = (int []){ 1, 2, 3 };
    return u + q.x + arr[1] + pp->y + ip[0];
}
_Bool b; long long ll = 1LL; double _Complex z;
double h = 0x1.8p3;
