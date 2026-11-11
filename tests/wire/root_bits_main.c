/* --root=big: the bit layer reads the rule `big` (three octets), though `small` stands first in the file. */
#include <stdio.h>
#include "root_bits.c"

int main(void) {
    static const uint8_t buf[3] = { 0xAB, 0xCD, 0xEF };
    big_t out;
    char err[256];
    size_t at = 0;
    if (!parse_bytes(buf, sizeof buf, &out, err, sizeof err, &at)) {
        printf("error: %s\n", err);
        return 1;
    }
    printf("tag=%u hi=%u lo=%u\n", (unsigned)out.tag, (unsigned)out.hi, (unsigned)out.lo);
    return 0;
}
