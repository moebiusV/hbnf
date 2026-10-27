int f(int n)
{
    int t = 0;
    switch (n) {
    case 0:
    case 1: t = 1; break;
    default: t = 2;
    }
    while (n-- > 0) t--;
    do t++; while (t < 0);
    if (t) t = 0; else if (n) t = 1; else t = 2;
    goto done;
done:
    return t ? t : -1;
}
void empty(void) { ; }
