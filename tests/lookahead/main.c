/* Lookahead: how each statement was read (a label's colon is not a :=). */
#include <stdio.h>
#include <string.h>

static int show(const void *n, node_kind_t kind, int enter, void *ctx) {
    (void)ctx;
    if (enter && kind == NODE_STATEMENT)
        printf("%s ", node_alt_name(kind, node_alt(n, kind)));
    return WALK_CONTINUE;
}

static void run(const char *text) {
    struct program_list out;
    char err[256], *nl;
    size_t line, col;
    printf("%-22s ", text);
    if (!parse_text(text, &out, err, sizeof err, &line, &col)) {
        if ((nl = strchr(err, '\n'))) *nl = 0;
        printf("refused: %s\n", err);
        return;
    }
    walk_program(&out, show, NULL);
    printf("\n");
}

int main(void) {
    run("a: b;");
    run("a := b;");
    run("a;");
    run("a : b; c := d; e;");
    run("a : = b;");
    run("a := := b;");
    run("a, b;");
    run("a :, b;");
    run("a =, b;");
    return 0;
}
