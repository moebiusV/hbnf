/* rollback.c: a driver for tests/emit/rollback.hbnf; prints the stack the emits left */
int main(int argc, char **argv) {
    char err[512];
    size_t l, c;
    top_t v = 0;
    int i;
    if (!parse_text(argv[1], &v, err, sizeof err, &l, &c)) { printf("error\n"); return 1; }
    for (i = 0; i < depth; i++) printf(i ? " %d" : "%d", stack[i]);
    printf("\n");
    return 0;
}
