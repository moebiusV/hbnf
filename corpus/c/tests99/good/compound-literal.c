struct p { int x, y; };
int f(struct p *);
int g(void)
{
    int *a = (int []){ 1, 2, 3 };
    struct p *q = &(struct p){ .x = 1, .y = 2 };
    return f(q) + a[1] + (int){ 5 };
}
