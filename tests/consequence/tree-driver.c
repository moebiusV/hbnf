/* tree-driver.c: parses the two texts on the command line with the grammar (root `cond`) and says whether their
   trees are the same (the dump of each, from --ast-tools), different, or whether neither is a sentence. */
#include <stdio.h>
#include <string.h>

static int one(const char *t, char *buf, size_t cap) {
    cond_t v;
    char err[256];
    size_t l, c;
    memset(&v, 0, sizeof v);
    if (!parse_text(t, &v, err, sizeof err, &l, &c)) { snprintf(buf, cap, "error"); return 0; }
    dump_cond(&v, buf, cap);
    return 1;
}

int main(int argc, char **argv) {
    char a[4096], b[4096];
    int ra, rb;
    if (argc < 3) return 2;
    ra = one(argv[1], a, sizeof a);
    rb = one(argv[2], b, sizeof b);
    if (!ra && !rb) puts("error");
    else if (ra && rb && strcmp(a, b) == 0) puts("same");
    else printf("different: %s | %s\n", a, b);
    return 0;
}
