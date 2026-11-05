#include <stdio.h>
#include <stdint.h>
#include "sample-driven.c"
int main (void)
{
    /* sample encodings, made by hand (nothing enumerates the leaves for us): add3 = prefix 111011111000, fields 10 11 12 */
    uint8_t add3[] = { 0xEF, 0x8A, 0xBC }, nop[] = { 0xEC, 0x80 };
    insn_t out; char err[256]; size_t at;
    if (!parse_bytes (add3, sizeof add3, &out, err, sizeof err, &at)) printf ("add3: %s\n", err);
    if (!parse_bytes (nop, sizeof nop, &out, err, sizeof err, &at)) printf ("nop: %s\n", err);
    return 0;
}
