/* time_xml_tree.c -- time parse_text of the XML grammar's generated C parser over one file, as time_format.c does,
 * and then count what the tree holds so that bench/libs.sh can check it against the other parsers: elements,
 * attributes (not the xmlns declarations) and the bytes of text that are not blanks.  The grammar reads the markup
 * and decodes nothing, so a reference is an item of its own here, and the walk gives it the length of the
 * character it stands for (&amp; and the other four are one byte, &#N; and &#xN; the UTF-8 length of N).
 * Built by concatenating the generated parser ahead of this file, with -DOUT_T=document_t.
 * Prints "ok BYTES MS RSS_KIB ELEMENTS ATTRIBUTES TEXT". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>

static long nel, nat, ntx;
static long blank(const char *s, size_t n) {
    long k = 0; size_t i;
    for (i = 0; i < n; i++) k += !(s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r');
    return k;
}
static long ref_bytes(const char *s, size_t n) {   /* s is "&...;" */
    unsigned long cp = 0;
    size_t i;
    if (n < 3 || s[1] != '#') return 1;
    if (s[2] == 'x') for (i = 3; i + 1 < n; i++) cp = cp * 16 + (s[i] <= '9' ? s[i] - '0' : (s[i] | 32) - 'a' + 10);
    else for (i = 2; i + 1 < n; i++) cp = cp * 10 + (s[i] - '0');
    return cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
}
static void visit(const void *node, node_kind_t kind, void *ctx) {
    (void)ctx;
    switch (kind) {
    case NODE_ELEMENT: nel++; break;
    case NODE_ATTRIBUTE: {
        hbnf_str q = ((const attribute_t *)node)->qname;
        nat += !!strncmp(hbnf_sp(q), "xmlns", hbnf_sn(q) < 5 ? hbnf_sn(q) : 5);
        break; }
    case NODE_CONTENT: {      /* a content item holds one of: an element, character data, a reference, a CDATA section, ...;
                               * _alt says which (from 1, in the order of content = *( element | chardata | reference | cdata | pi | remark )),
                               * and the fields of the others share its space */
        const content_t *c = node;
        if (c->_alt == 3) { if (c->reference._alt == 1) ntx += ref_bytes(hbnf_sp(c->reference.simple_ref), hbnf_sn(c->reference.simple_ref)); }
        else if (c->_alt == 2) ntx += blank(hbnf_sp(c->chardata), hbnf_sn(c->chardata));
        break; }
    case NODE_CDATA: { hbnf_str a = ((const cdata_t *)node)->till_x93x93x62; ntx += blank(hbnf_sp(a), hbnf_sn(a)); break; }
    default: break;
    }
}

int main(int argc, char **argv) {
    FILE *f;
    char *buf, err[512];
    long len;
    size_t line, col;
    OUT_T out;
    struct timespec t0, t1;
    struct rusage ru;
    double ms;
    int ok;

    if (argc < 2 || !(f = fopen(argv[1], "rb"))) return 2;
    fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
    buf = malloc(len + 1);
    if (fread(buf, 1, len, f) != (size_t)len) return 2;
    buf[len] = 0; fclose(f);
    clock_gettime(CLOCK_MONOTONIC, &t0);
    ok = parse_text(buf, &out, err, sizeof err, &line, &col);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
    getrusage(RUSAGE_SELF, &ru);
    if (!ok) { fprintf(stderr, "%s\n", err); printf("FAIL %ld %.2f %ld\n", len, ms, ru.ru_maxrss); return 1; }
    visit_document(&out, visit, 0);
    printf("ok %ld %.2f %ld %ld %ld %ld\n", len, ms, ru.ru_maxrss, nel, nat, ntx);
    return 0;
}
