/* Spans and parents (--spans --parents): where each node of tests/ast/ast.hbnf's
   tree is in the text, and which node holds it. */
#include <stdio.h>
#include <string.h>

static const char *text = "set a 1;\nrun b;\n{ set c \"x\"; }\n";

static int show(const void *n, node_kind_t kind, int enter, void *ctx) {
    size_t s, e, line, col;
    node_kind_t pk;
    const void *up;
    (void)ctx;
    if (!enter) return WALK_CONTINUE;
    if (!node_span(n, kind, &s, &e)) return WALK_CONTINUE;
    node_where(text, s, &line, &col);
    up = node_parent(n, kind, &pk);
    printf("%-6s %2zu..%-2zu %zu:%zu in %-6s \"%.*s\"\n", node_kind_name(kind), s, e,
           line, col, up ? node_kind_name(pk) : "-", (int)(e - s), text + s);
    return WALK_CONTINUE;
}

int main(void) {
    struct config_list out;
    char err[256];
    size_t line, col;
    if (!parse_text(text, &out, err, sizeof err, &line, &col)) {
        printf("error: %s\n", err);
        return 1;
    }
    link_config(&out);
    walk_config(&out, show, NULL);
    return 0;
}
