int count(int n)
{
    int i, total = 0;
    int a[10];
    for (i = 0; i < n; i++) {
        if (i % 2 == 0)
            continue;
        else if (i > 7)
            break;
        total += i;
    }
    for (;;) break;
    while (n-- > 0)
        total--;
    do total++; while (total < 0);
    switch (n) {
    case 0:
    case 1: total = 1; break;
    default: total = 2;
    }
    goto done;
done:
    return total ? total : -1;
}
void nothing(void) { ; }
void blocks(void)
{
    int x = 1;
    {
        int x = 2;
        x++;
    }
    {
        struct s { int a; } v;
        v.a = x;
    }
}
