/* Text after a 3-bit field: read at bit 3, shifted. */
#include <stdio.h>
#include <string.h>
#include "mixed3.c"

static void show(const char *what, const char *in, size_t n) {
    doc_t out;
    char err[512], text[64];
    size_t line = 0, col = 0;
    memcpy(text, in, n);
    text[n] = 0;
    if (parse_text(text, &out, err, sizeof err, &line, &col))
        printf("%s: flag=%u label=%s pad=%u\n", what,
               (unsigned)out.record.flag, out.record.label,
               (unsigned)out.record.pad);
    else
        printf("%s: error\n%s\n", what, err);
}

int main(void) {
    /* flag 101, "abc", pad 00000: 10101100 00101100 01001100 01100000 */
    show("abc", "REC:\xac\x2c\x4c\x60", 8);
    /* flag 000, "Z" = 0x5a: 00001011 01000000 */
    show("Z", "REC:\x0b\x40", 6);
    return 0;
}
