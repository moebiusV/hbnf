/* tests/compare.sh's driver: parse two pfctl configs, skip the first's
   macro definitions, and compare the rules one by one with the generated
   compare_rule (--compare).  Exit 0 when every rule is equal. */
int main(int argc, char **argv) {
    char err[512];
    size_t line, col, k = 0;
    struct ruleset_list a, b;
    ruleset_t *x, *y;

    if (argc != 3)
        return 2;
    if (!parse_file(argv[1], &a, err, sizeof err, &line, &col) ||
        !parse_file(argv[2], &b, err, sizeof err, &line, &col)) {
        printf("%zu: %s\n", line, err);
        return 2;
    }
    for (x = TAILQ_FIRST(&a); x && x->rule.varset.string; x = TAILQ_NEXT(x, _link))
        ;
    for (y = TAILQ_FIRST(&b); x && y; x = TAILQ_NEXT(x, _link), y = TAILQ_NEXT(y, _link), k++)
        if (!compare_rule(&x->rule, &y->rule)) {
            printf("rule %zu differs\n", k + 1);
            return 1;
        }
    if (x || y) {
        printf("different number of rules\n");
        return 1;
    }
    printf("%zu rules equal\n", k);
    return 0;
}
