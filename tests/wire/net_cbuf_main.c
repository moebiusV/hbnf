/* The C interface's buffer arguments: a buffer that is too small says how big it
   must be, and a NULL buffer only counts.  (The Rust interface returns a Vec.) */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "net.c"

#define ETH "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55"

int main(void) {
    static const uint8_t tcp[] = ETH "\x08\x00"
        "\x45\x00\x00\x2c\x00\x01\x00\x00\x40\x06\x00\x00"
        "\xc0\xa8\x00\x01\xc0\xa8\x00\x02"
        "\x1f\x90\x00\x50\x00\x00\x00\x01\x00\x00\x00\x00\x50\x02\x20\x00"
        "\x00\x00\x00\x00"
        "ping";
    bnf_ethernet_t e;
    char err[64];
    size_t at;
    parse_bytes(tcp, sizeof tcp - 1, &e, err, sizeof err, &at);
    {
            uint8_t tiny[10];
            size_t m = 0;
            char er[128];
            printf("buffer too small: %s",
                   emit_bytes(&e, tiny, sizeof tiny, &m, er, sizeof er)
                   ? "written\n" : "");
            printf("%s (needs %zu)\n", er, m);
            emit_bytes(&e, NULL, 0, &m, er, sizeof er);
            printf("counting only: %zu octets\n", m);
        }
    free_arena();
    return 0;
}
