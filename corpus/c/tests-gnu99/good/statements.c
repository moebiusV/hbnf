int f(int n)
{
    __label__ done, again;
    int t = 0;
    switch (n) {
    case 1 ... 5: t = 1; break;
    case 7:
    default: t = 2;
    }
again:
    t++;
    if (t < 3) goto again;
    int u = t;
    {
    inner:
        ;
    }
    int nested(int q) { return q + n; }
    t = nested(u);
done:
    return t;
}
void g(void) { x: }
