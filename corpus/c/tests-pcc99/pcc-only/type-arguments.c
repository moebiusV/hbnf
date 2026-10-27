typedef int T;
int use(int n)
{
    return va_arg_like(n, int) + va_arg_like(n, T *) + va_arg_like(n, struct { int a; });
}
