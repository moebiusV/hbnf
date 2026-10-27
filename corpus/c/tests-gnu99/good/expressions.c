int f(int x, int y)
{
    int a = ({ int t = x; t * 2; });
    int b = x ?: y;
    __typeof__(x) c = x;
    typeof(x + y) d = y;
    int e = (__extension__ 5) + __alignof__(int) + __alignof(c);
    double _Complex z = 1.0 + 2.0i;
    double re = __real__ z, im = __imag__ z;
    void *lp = &&out;
    __builtin_va_list ap;
    int o = __builtin_offsetof(struct { int i; int j[2]; }, j[1]);
    int ch = __builtin_choose_expr(1, 2, 3);
    int tc = __builtin_types_compatible_p(int, long);
    goto *lp;
out:
    return a + b + c + d + e + o + ch + tc;
}
