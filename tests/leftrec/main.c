/* tests/leftrec.sh's driver: parse each file and print its entries, a
   sum folded to the left, or the error. */
static long long fold(const struct sum_list *h) {
    const sum_t *e;
    long long acc = 0;
    for (e = h->head; e; e = e->_link)
        switch (e->kind) {
        case SUM_BASE: acc = e->int_; break;    /* the first entry */
        case SUM_OP1:  acc += e->int_; break;   /* + */
        case SUM_OP2:  acc -= e->int_; break;   /* - */
        }
    return acc;
}

static void show(const entry_t *n, int big) {
    const host_list_t *h;
    const sum_t *s;
    const string_t *w;
    size_t k = 0;

    switch (n->kind) {
    case ENTRY_HOSTS:
        printf("  hosts");
        for (h = n->host_list.head; h; h = h->_link)
            printf(" %s", h->host);
        break;
    case ENTRY_CALC:
        printf("  calc");
        for (s = n->sum.head; s; s = s->_link, k++)
            if (!big)
                printf("%s%lld", s->kind == SUM_BASE ? " "
                    : s->kind == SUM_OP1 ? " + " : " - ", s->int_);
        if (big)
            printf(" (%zu terms)", k);
        printf(" = %lld", fold(&n->sum));
        break;
    case ENTRY_WORDS:
        printf("  words");
        for (w = n->string.head; w; w = w->_link)
            printf(" %s", w->word);
        break;
    }
    printf("\n");
}

int main(int argc, char **argv) {
    int i;

    for (i = 1; i < argc; i++) {
        char err[512];
        size_t line, col, k = 0;
        struct config_list out;
        const config_t *c;
        if (parse_file(argv[i], &out, err, sizeof err, &line, &col)) {
            for (c = out.head; c; c = c->_link)
                k++;
            printf("%s: %zu entries\n", argv[i], k);
            for (c = out.head; c; c = c->_link)
                show(&c->entry, strstr(argv[i], "big") != NULL);
        } else
            printf("%s:%zu: %s\n", argv[i], line, err);
        free_config(&out);
    }
    return 0;
}
