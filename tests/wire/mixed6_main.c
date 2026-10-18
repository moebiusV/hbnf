/* A bit rule of a mixed grammar, written: %emit fills in len. */
#include <stdio.h>
#include <string.h>
#include "mixed6.c"

int main(void) {
    frame_t f;
    uint8_t buf[64];
    size_t nbits = 0, i;
    char err[256];
    static const uint8_t body[] = { 'h', 'e', 'l', 'l', 'o' };
    memset(&f, 0, sizeof f);
    f.len = 99;                       /* %emit replaces it */
    f.body.ptr = body;  f.body.len = sizeof body;
    f.tag = "ab";
    if (!emit_bits_frame(&f, buf, sizeof buf, &nbits, err, sizeof err))
        printf("error: %s\n", err);
    else {
        printf("%zu bits:", nbits);
        for (i = 0; i < (nbits + 7) / 8; i++) printf(" %02x", buf[i]);
        printf("\n");
    }
    f.tag = "";                      /* a token is text; "" writes nothing */
    nbits = 0;
    if (emit_bits_frame(&f, NULL, 0, &nbits, err, sizeof err))
        printf("count only: %zu bits\n", nbits);
    return 0;
}
