/* A bit rule that ends inside an octet, then text: refused, with the reason. */
#include <stdio.h>
#include <string.h>
#include "mixed3.c"

int main(void) {
    doc_t out;
    char err[512];
    size_t line = 0, col = 0;
    if (parse_text("REC:\xa0" "abc", &out, err, sizeof err, &line, &col))
        printf("accepted\n");
    else
        printf("error\n%s\n", err);
    return 0;
}
