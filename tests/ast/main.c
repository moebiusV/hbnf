/* The walk of tests/ast/ast.hbnf's tree: each node, how the walk got to it, and
   the alternative it took. */
#include <stdio.h>

static void path(const hbnf_frame_t *at) {
    if (at->up) { path(at->up); printf(" > "); }
    printf("%s", node_kind_name(at->kind));
    if (at->alt) printf("[%s]", node_alt_name(at->kind, at->alt));
    if (at->field) printf(".%s", at->field);
}

static walk_result_t show(const hbnf_frame_t *at, int enter, void *ctx) {
    int *skip_blocks = ctx;
    if (!enter) return WALK_CONTINUE;
    path(at);
    printf("\n");
    if (*skip_blocks && at->kind == NODE_BLOCK) return WALK_SKIP;
    return WALK_CONTINUE;
}

static walk_result_t count(const hbnf_frame_t *at, int enter, void *ctx) {
    int *n = ctx;
    if (enter && at->kind == NODE_ENTRY && ++*n == 2) return WALK_STOP;
    return WALK_CONTINUE;
}

int main(void) {
    struct config_list out;
    char err[256];
    size_t line, col;
    int skip = 0, n = 0;
    if (!parse_text("set a 1; run b; { set c \"x\"; set d e; }", &out, err,
                    sizeof err, &line, &col)) {
        printf("error: %s\n", err);
        return 1;
    }
    printf("== all\n");
    walk_config(&out, NULL, NULL, show, &skip);
    printf("== blocks skipped\n");
    skip = 1;
    walk_config(&out, NULL, NULL, show, &skip);
    printf("== stop at the second entry: walk returned %s\n",
           walk_config(&out, NULL, NULL, count, &n) ? "true" : "false");
    return 0;
}
