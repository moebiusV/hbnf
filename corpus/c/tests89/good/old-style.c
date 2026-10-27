char *strcpy2(dst, src)
register char *dst, *src;
{
    char *r = dst;
    while (*dst++ = *src++)
        ;
    return r;
}
int cmp(a, b) char *a; char *b; { return *a - *b; }
float scale(x) float x; { return x; }
