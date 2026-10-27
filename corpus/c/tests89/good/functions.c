/* old-style and prototype definitions, implicit int, a function pointer */
int add(a, b)
    int a;
    int b;
{
    return a + b;
}

int sub(int a, int b) { return a - b; }

static twice(x) { return x * 2; }

int apply(int (*f)(int, int), int x, int y)
{
    return (*f)(x, y);
}

int printf(const char *, ...);

main()
{
    int (*op)(int, int) = add;
    printf("%d %d\n", apply(op, 2, 3), twice(4));
    return 0;
}
