/* tests/syntax.sh's driver: parse each file, print its entries and what
   the %action counted, or the error. */
static size_t entries(struct config_list *h) {
    size_t k = 0;
    config_t *n;
    for (n = h->head; n; n = n->_link)     /* hbnf's own list */
        k++;
    return k;
}

int main(int argc, char **argv) {
    int i;

    for (i = 1; i < argc; i++) {
        char err[512];
        size_t line, col;
        struct config_list out;
        modes_seen = 0;
        if (parse_file(argv[i], &out, err, sizeof err, &line, &col))
            printf("%s: %zu entries, %d set mode\n", argv[i], entries(&out), modes_seen);
        else
            printf("%s:%zu: %s\n", argv[i], line, err);
        free_config(&out);
    }
    return 0;
}
