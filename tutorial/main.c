/* Read a shopping list with the parser hbnf made, and use the tree. */
#include <stdio.h>
#include "shopping.c"

static void add_up(const void *node, node_kind_t kind, void *ctx) {
    if (kind == NODE_ITEM)
        *(long long *)ctx += ((const item_t *)node)->qty;
}

int main(void) {
    const char *text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    struct list_list list;
    char err[512];
    size_t line, col;

    if (!parse_text(text, &list, err, sizeof err, &line, &col)) {
        fprintf(stderr, "%s\n", err);          /* the message points at the text */
        return 1;
    }
    for (const list_t *n = list.head; n; n = n->_link) {
        printf("%lld x %s", n->item.qty, n->item.name);
        if (n->item.item_1.head)                /* [ "from" shop ] is a list of 0 or 1 */
            printf(" (from %s)", n->item.item_1.head->shop);
        printf("\n");
    }
    long long total = 0;
    visit_list(&list, add_up, &total);          /* every node, parent before children */
    printf("total: %lld items\n", total);
    return 0;
}
