/* The walk of tests/ast/ast.hbnf's tree with node_walk, node_kids, node_dump and
   node_equal. */
#include <stdio.h>
#include <stdlib.h>

struct depth { int d, skip_blocks; };

static int show_node(const void *n, node_kind_t kind, int enter, void *ctx) {
    struct depth *s = ctx;
    int alt = node_alt(n, kind);
    if (!enter) { s->d--; return WALK_CONTINUE; }
    printf("%*s%s", s->d * 2, "", node_kind_name(kind));
    if (alt) printf("[%s]", node_alt_name(kind, alt));
    printf("\n");
    if (s->skip_blocks && kind == NODE_BLOCK) return WALK_SKIP;
    s->d++;
    return WALK_CONTINUE;
}

static int count(const void *n, node_kind_t kind, int enter, void *ctx) {
    int *k = ctx;
    (void)n;
    if (enter && kind == NODE_ENTRY && ++*k == 2) return WALK_STOP;
    return WALK_CONTINUE;
}

static void show_kid(const hbnf_kid_t *k, void *ctx) {
    static const char *tn[] = { "node", "str", "int", "uint", "bool", "enum" };
    (void)ctx;
    printf("  %s %s", k->name, tn[k->type]);
    if (k->type == KID_NODE) printf(" %s", node_kind_name(k->kind));
    if (k->type == KID_STR) printf(" \"%s\"", k->str);
    printf("\n");
}

int main(void) {
    struct config_list out;
    char err[256];
    size_t line, col;
    struct depth d = { 0, 0 };
    int n = 0;
    if (!parse_text("set a 1; run b; { set c \"x\"; set d e; }", &out, err,
                    sizeof err, &line, &col)) {
        printf("error: %s\n", err);
        return 1;
    }
    printf("== all\n");
    walk_config(&out, show_node, &d);
    printf("== blocks skipped\n");
    d.d = 0;  d.skip_blocks = 1;
    walk_config(&out, show_node, &d);
    printf("== dump\n");
    {
        size_t m = dump_config(&out, NULL, 0);
        char *b = (char *)malloc(m + 1);
        dump_config(&out, b, m + 1);
        printf("%s\n", b);
        free(b);
    }
    printf("== children of the first entry\n");
    node_kids(out.head, NODE_CONFIG, show_kid, NULL);
    printf("== equal\n");
    {
        struct config_list same, other;
        parse_text("set a 1; run b; { set c \"x\"; set d e; }", &same, err,
                   sizeof err, &line, &col);
        parse_text("set a 2; run b; { set c \"x\"; set d e; }", &other, err,
                   sizeof err, &line, &col);
        printf("same text: %d\n", node_equal(out.head, NODE_CONFIG, same.head,
                                             NODE_CONFIG));
        printf("other text: %d\n", node_equal(out.head, NODE_CONFIG,
                                              other.head, NODE_CONFIG));
        printf("second entries of both: %d\n",
               node_equal(out.head->_link, NODE_CONFIG, other.head->_link,
                          NODE_CONFIG));
    }
    printf("== stop at the second entry: walk returned %s\n",
           walk_config(&out, count, &n) ? "true" : "false");
    return 0;
}
