/* run.c: a driver for tests/emit/run.hbnf; the generated parser is included above it */
#include <stdio.h>
int main(int argc, char **argv) {
    char err[512];
    size_t l, c;
    list_t v = 0;
    if (!parse_text(argv[1], &v, err, sizeof err, &l, &c)) {
        printf("error %zu:%zu\n", l, c);
        return 1;
    }
    printf("%d\n", (int)v);
    return 0;
}
