/* Forks: which alternative each rule ended up with. */
#include <stdio.h>
#include <string.h>

static int ok(const char *t) {
    ROOT out; char err[256], *nl; size_t l, c;
    int r = parse_text(t, &out, err, sizeof err, &l, &c);
    if (!r && (nl = strchr(err, '\n'))) *nl = 0;
    printf("%-14s %s\n", t, r ? "accepted" : err);
    return r;
}
int main(void) {
    ok("a x;");        /* short */
    ok("a x y;");      /* needs the long alternative: x is tried first */
    ok("b <=;");       /* needs <= although < matches first */
    ok("b <;");
    ok("b <>;");
    ok("c x x y;");    /* the first fork is short, then long */
    ok("c x y x;");    /* the first fork must give up a y */
    ok("d x y z!");    /* nested: first inside outer, then the rest */
    ok("d x z!");
    ok("a x z;");      /* refused */
    return 0;
}
