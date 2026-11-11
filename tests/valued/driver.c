/* driver.c: for the grammars of tests/valued/, whose root is `top`; the generated parser is included above it */
#include <stdio.h>
int main(int argc, char **argv) {
    char err[512];
    size_t l, c;
    top_t v = 0;
    if (!parse_text(argv[1], &v, err, sizeof err, &l, &c)) {
        printf("error %zu:%zu\n", l, c);
        return 1;
    }
    printf("ok %d\n", (int)v);
    return 0;
}
