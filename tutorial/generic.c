/* Tools that work on any hbnf tree (C, generated with --ast --ast-tools --spans --writer):
   walk it, dump it, find where a node was in the text, and write it back as text. */
#include <stdio.h>
#include <stdlib.h>
#include "shopping.c"

/* node_walk calls this on entering (enter = 1) and leaving each node. */
static int show(const void *node, node_kind_t kind, int enter, void *ctx) {
    int *depth = ctx;
    if (!enter) { (*depth)--; return WALK_CONTINUE; }
    size_t start, end;
    node_span(node, kind, &start, &end);
    printf("%*s%s  bytes %zu-%zu\n", *depth * 2, "", node_kind_name(kind), start, end);
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
    walk_list(&list, show, &depth);                     /* the shape of the tree */

    size_t n = dump_list(&list, NULL, 0);               /* an S-expression, length first */
    char *s = malloc(n + 1);
    dump_list(&list, s, n + 1);
    printf("%s\n", s);
    free(s);

    node_where(text, list.head->_link->_pos, &line, &col);   /* byte offset -> line, column */
    printf("the second item starts at line %zu, column %zu\n", line, col);

    char out[256];
    write_list(&list, out, sizeof out);                 /* the tree, as text again */
    printf("written: %s\n", out);
    return 0;
}
