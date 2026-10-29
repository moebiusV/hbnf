/* runs.c: a driver for tests/emit/runs.hbnf: the value, the depth of the stack and the sum of what is on it */
#include <stdio.h>
int main(int argc, char **argv) {
    char err[512];
    size_t l, c;
    top_t v = 0;
    if (!parse_text(argv[1], &v, err, sizeof err, &l, &c)) {
        printf("error %zu:%zu\n", l, c);
        return 1;
    }
    int sum = 0;
    for (int i = 0; i < depth; i++) sum += stack[i];
    printf("%d %d %d\n", (int)v, depth, sum);
    return 0;
}
