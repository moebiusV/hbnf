/* The walker and the dump the generator makes (--ast --ast-tools), the same in every language. */
#include <stdio.h>
#include <stdlib.h>
#include "shopping.c"

static int show(const void *node, node_kind_t kind, int enter, void *ctx) {
    int *depth = ctx;
    (void)node;
    if (!enter) { (*depth)--; return WALK_CONTINUE; }
    printf("%*s%s\n", *depth * 2, "", node_kind_name(kind));
    (*depth)++;
    return WALK_CONTINUE;
}

int main(void) {
    const char *text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    struct list_list list;
    char err[512];
    size_t line, col;
    if (!parse_text(text, &list, err, sizeof err, &line, &col)) { fprintf(stderr, "%s\n", err); return 1; }
    int depth = 0;
    walk_list(&list, show, &depth);
    size_t n = dump_list(&list, NULL, 0);
    char *s = malloc(n + 1);
    dump_list(&list, s, n + 1);
    printf("%s\n", s);
    free(s);
    return 0;
}
