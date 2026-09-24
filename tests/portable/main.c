/* tests/portable.sh's C driver: parse each file and print what it holds,
   as main.rs, main.zig and portable_main.adb do. */
static char *slurp(const char *path) {
    FILE *f = fopen(path, "rb");
    char *s;
    long n;
    if (!f || fseek(f, 0, SEEK_END) || (n = ftell(f)) < 0 || fseek(f, 0, SEEK_SET)) {
        perror(path);
        exit(2);
    }
    s = malloc((size_t)n + 1);
    if (!s || fread(s, 1, (size_t)n, f) != (size_t)n)
        exit(2);
    s[n] = '\0';
    fclose(f);
    return s;
}

int main(int argc, char **argv) {
    int i;

    for (i = 1; i < argc; i++) {
        char err[512], *text = slurp(argv[i]);
        size_t line, col;
        config_t c;
        const host_list_t *h;
        const sum_t *s;
        const modes_t *m;
        const pair_t *p;
        long long acc = 0;

        if (!parse_text(text, &c, err, sizeof err, &line, &col)) {
            printf("%s: rejected at line %zu\n", argv[i], line);
            free(text);
            continue;
        }
        printf("%s: hosts", argv[i]);
        for (h = c.host_list.head; h; h = h->_link)
            printf(" %s", h->host);
        printf("; calc");
        for (s = c.sum.head; s; s = s->_link) {
            if (s == c.sum.head) {          /* the base */
                acc = s->int_;
                printf(" %lld", s->int_);
            } else {
                acc += s->op == OP_OP1 ? s->int_ : -s->int_;
                printf(" %s %lld", s->op == OP_OP1 ? "+" : "-", s->int_);
            }
        }
        printf(" = %lld; modes", acc);
        for (m = c.modes.head; m; m = m->_link)
            printf(" %s", m->modeset.mode == MODE_FAST ? "fast" : "slow");
        printf("; pair");
        for (p = c.pair.head; p; p = p->_link)
            printf(" %s", p->host);
        printf("\n");
        free_config(&c);
        free(text);
    }
    return 0;
}
