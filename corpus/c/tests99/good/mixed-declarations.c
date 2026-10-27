int f(int n)
{
    int a = 1;
    a += n;
    int b = a * 2;
    for (int i = 0; i < n; i++) {
        int sq = i * i;
        b += sq;
    }
    for (int i = 0, j = 1; i < j; i++) b++;
    return b;
}
