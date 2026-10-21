/* How a walker, a dump and a pretty-printer are made: plain functions over the typed tree.
   Nothing here is generated; it is what you would write.  (The parse is messy on purpose.) */
#include <stdio.h>
#include "shopping.c"

/* Walk: one function per rule, children in the order the grammar has them. */
static void my_walk_shop(const char *shop, int depth) {
    printf("%*sshop %s\n", depth * 2, "", shop);
}

static void my_walk_item(const item_t *item, int depth) {
    printf("%*sitem\n", depth * 2, "");
    printf("%*sqty %lld\n", (depth + 1) * 2, "", item->qty);
    printf("%*sname %s\n", (depth + 1) * 2, "", item->name);
    for (const item_1_t *from = item->item_1.head; from; from = from->_link) {
        printf("%*sfrom\n", (depth + 1) * 2, "");
        my_walk_shop(from->shop, depth + 2);
    }
}

static void my_walk_list(const struct list_list *list) {
    printf("list\n");
    for (const list_t *n = list->head; n; n = n->_link)
        my_walk_item(&n->item, 1);
}

/* Dump: the same recursion, but it writes an S-expression. */
static void my_dump_item(const item_t *item) {
    printf("(item (qty %lld) (name \"%s\")", item->qty, item->name);
    for (const item_1_t *from = item->item_1.head; from; from = from->_link)
        printf(" (from (shop \"%s\"))", from->shop);
    printf(")");
}

static void my_dump_list(const struct list_list *list) {
    printf("(list");
    for (const list_t *n = list->head; n; n = n->_link) {
        printf(" ");
        my_dump_item(&n->item);
    }
    printf(")\n");
}

/* Pretty-print: the text the grammar reads, in one canonical layout. */
static void my_print_list(const struct list_list *list) {
    for (const list_t *n = list->head; n; n = n->_link) {
        printf("buy %lld %s", n->item.qty, n->item.name);
        if (n->item.item_1.head)
            printf(" from %s", n->item.item_1.head->shop);
        printf(";\n");
    }
}

int main(void) {
    const char *text = "buy  2   apples ;\n  buy 1\n milk from   corner-shop ;";
    struct list_list list;
    char err[512];
    size_t line, col;
    if (!parse_text(text, &list, err, sizeof err, &line, &col)) {
        fprintf(stderr, "%s\n", err);
        return 1;
    }
    printf("== walk\n");
    my_walk_list(&list);
    printf("== dump\n");
    my_dump_list(&list);
    printf("== print\n");
    my_print_list(&list);
    return 0;
}
