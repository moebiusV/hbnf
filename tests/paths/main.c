/* Errors that say where the parser was (--paths): tests/ast/ast.hbnf, bad input. */
#include <stdio.h>

static void try(const char *text) {
    struct config_list out;
    char err[512];
    size_t line, col;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("ok: %s\n", text);
    else
        printf("%s\n%s\n", text, err);
}

int main(void) {
    try("set a 1; run b;");
    try("set a ;");
    try("run ;");
    try("set a 1; { run b; { set c ; } }");
    try("{ run b;");
    try("go a;");
    return 0;
}
