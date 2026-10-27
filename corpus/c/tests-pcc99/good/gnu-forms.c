struct p { int x, y; };
int f(int x, int y)
{
    int a = ({ int t = x; t * 2; });
    int b = x ?: y;
    __typeof__(x) c = x;
    typeof(x + y) d = y;
    void *lp = &&out;
    int o = __builtin_offsetof(struct p, y);
    struct p v = { y: 1, x: 2 };
    int arr[8] = { [2 ... 4] = 9 };
    int e = __alignof__(int);
    switch (x) { case 1 ... 5: a = 1; break; default: ; }
    goto *lp;
out:
    return a + b + c + d + o + v.x + arr[3] + e;
}
struct empty { };
int empty_init[3] = { };
struct t { int x; ; int y; ; };
static x2;
main2() { return 0; }
int old(a, b) int a, b; { return a; }
int va(int n, ...) { return __builtin_offsetof(struct p, x); }
