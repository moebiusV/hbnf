/* Context: which way each expression statement was read. */
#include <stdio.h>
#include <string.h>

/* the outermost expression of each statement: how it was read */
static int show(const void *n, node_kind_t kind, int enter, void *ctx) {
    int *depth = ctx;
    if (kind != NODE_EXPR) return WALK_CONTINUE;
    if (!enter) { --*depth; return WALK_CONTINUE; }
    if ((*depth)++ == 0)
        printf("%s ", node_alt_name(kind, node_alt(n, kind)));
    return WALK_CONTINUE;
}

static void run(const char *what, const char *text) {
    struct program_list out;
    char err[256];
    size_t line, col;
    printf("%-34s ", what);
    if (!parse_text(text, &out, err, sizeof err, &line, &col)) {
        char *nl = strchr(err, '\n');
        if (nl) *nl = 0;
        printf("error: %s\n", err);
        return;
    }
    {
        int depth = 0;
        walk_program(&out, show, &depth);
    }
    printf("\n");
}

int main(void) {
    run("(A)*0, A a typedef", "typedef int A; (A) * 0;");
    run("(B)*0, B a variable", "int B; (B) * 0;");
    run("(C)*0, C not declared", "(C) * 0;");
    run("T typedef inside a block, used in", "{ typedef int T; (T) * 1; }");
    run("... and after it (T is gone)", "{ typedef int T; } (T) * 1;");
    run("a guess that bound and gave up", "int Q; (Q) * 0;");
    return 0;
}
