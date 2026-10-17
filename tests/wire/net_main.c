#include <stdio.h>
#include "net.c"

static void show(const char *what, const uint8_t *b, size_t n) {
    bnf_ethernet_t e;
    char err[256];
    size_t at = 0;
    if (!parse_bytes(b, n, &e, err, sizeof err, &at)) {
        printf("%s: error at octet %zu: %s\n", what, at, err);
        return;
    }
    printf("%s: ethertype=%04x kind=%d", what, (unsigned)e.ethertype, e.payload.kind);
    if (e.payload.kind == 1) {
        bnf_ipv4_t *ip = &e.payload.u.a1.ip;
        printf(" ipv4 ihl=%u len=%u ttl=%u proto=%u src=%08x dst=%08x opts=%zu",
               ip->ihl, ip->total_length, ip->ttl, ip->protocol, ip->src,
               ip->dst, ip->options.len);
        if (ip->payload.kind == 1)
            printf(" tcp %u>%u seq=%u syn=%u data=%zu", ip->payload.u.a1.t.src_port,
                   ip->payload.u.a1.t.dst_port, ip->payload.u.a1.t.seq_num,
                   ip->payload.u.a1.t.syn, ip->payload.u.a1.t.payload.len);
        else if (ip->payload.kind == 2)
            printf(" udp %u>%u len=%u data=%zu", ip->payload.u.a2.u.src_port,
                   ip->payload.u.a2.u.dst_port, ip->payload.u.a2.u.length,
                   ip->payload.u.a2.u.payload.len);
        else
            printf(" data=%zu", ip->payload.u.a3.rest.len);
    } else if (e.payload.kind == 2)
        printf(" arp oper=%u spa=%08x tpa=%08x", e.payload.u.a2.a.oper,
               e.payload.u.a2.a.spa, e.payload.u.a2.a.tpa);
    else if (e.payload.kind == 3)
        printf(" ipv6 flow=%05x next=%u hop=%u data=%zu", e.payload.u.a3.v6.flow_label,
               e.payload.u.a3.v6.next_header, e.payload.u.a3.v6.hop_limit,
               e.payload.u.a3.v6.payload.len);
    else if (e.payload.kind == 4)
        printf(" raw=%zu", e.payload.u.a4.rest.len);
    printf("\n");

    /* and back: the bytes read are the bytes written */
    {
        uint8_t out[256];
        size_t m = 0;
        if (!emit_bytes(&e, out, sizeof out, &m, err, sizeof err))
            printf("  emit: error: %s\n", err);
        else if (m == n && memcmp(out, b, n) == 0)
            printf("  emit: %zu octets, identical\n", m);
        else
            printf("  emit: DIFFERENT (%zu octets)\n", m);
    }
    free_arena();
}

static void bad_emit(const char *what, bnf_ethernet_t *e) {
    uint8_t out[256];
    char err[256];
    size_t m = 0;
    if (emit_bytes(e, out, sizeof out, &m, err, sizeof err))
        printf("%s: written (%zu octets)\n", what, m);
    else
        printf("%s: %s\n", what, err);
}

#define ETH "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55"

int main(void) {
    static const uint8_t ip[] = ETH "\x08\x00"
        "\x46\x00\x00\x20\x12\x34\x40\x00\x40\x01\xab\xcd"
        "\x0a\x00\x00\x01\x0a\x00\x00\x02"
        "\x01\x01\x01\x00"                       /* options (ihl 6) */
        "hi!!";
    static const uint8_t tcp[] = ETH "\x08\x00"
        "\x45\x00\x00\x2c\x00\x01\x00\x00\x40\x06\x00\x00"
        "\xc0\xa8\x00\x01\xc0\xa8\x00\x02"
        "\x1f\x90\x00\x50\x00\x00\x00\x01\x00\x00\x00\x00\x50\x02\x20\x00"
        "\x00\x00\x00\x00"
        "ping";
    static const uint8_t udp[] = ETH "\x08\x00"
        "\x45\x00\x00\x1f\x00\x02\x00\x00\x40\x11\x00\x00"
        "\x0a\x00\x00\x01\x0a\x00\x00\x02"
        "\x00\x35\x12\x34\x00\x0b\x00\x00" "abc";
    static const uint8_t arp[] = ETH "\x08\x06"
        "\x00\x01\x08\x00\x06\x04\x00\x01"
        "\x00\x11\x22\x33\x44\x55\xc0\xa8\x00\x01"
        "\x00\x00\x00\x00\x00\x00\xc0\xa8\x00\x02";
    static const uint8_t v6[] = ETH "\x86\xdd"
        "\x60\x01\x23\x45\x00\x04\x11\x40"
        "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"
        "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02"
        "abcd";
    static const uint8_t other[] = ETH "\x88\xcc\x01\x02";   /* LLDP: not listed */
    show("ipv4", ip, sizeof ip - 1);
    show("tcp", tcp, sizeof tcp - 1);
    show("udp", udp, sizeof udp - 1);
    show("arp", arp, sizeof arp - 1);
    show("ipv6", v6, sizeof v6 - 1);
    show("unlisted ethertype", other, sizeof other - 1);
    show("short", ip, 10);

    {
        bnf_ethernet_t e;
        char err[64];
        size_t at;
        parse_bytes(tcp, sizeof tcp - 1, &e, err, sizeof err, &at);
        {
            bnf_ethernet_t c = e;
            c.payload.u.a1.ip.ihl = 16;
            bad_emit("ihl 16", &c);
        }
        {
            bnf_ethernet_t c = e;
            c.payload.u.a1.ip.options.len = 4;
            bad_emit("options longer than ihl says", &c);
        }
        {
            bnf_ethernet_t c = e;
            c.payload.kind = 2;
            bad_emit("arp payload for an ipv4 ethertype", &c);
        }
        {
            bnf_ethernet_t c = e;
            c.ethertype = 0x1234;
            bad_emit("ethertype not in the list", &c);
        }
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
    }
    return 0;
}
