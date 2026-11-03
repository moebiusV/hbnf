/* libexpat, the XML parser Python's pyexpat and xml.etree, Firefox and Apache are built on: it is event driven and
 * builds no tree.  Two modes, one process each: "events" sets handlers that only count (elements, attributes), and
 * "copy" sets handlers that copy every name, attribute and run of text into growing arrays, a cheap tree
 * (a node per element with its parent, its attributes and the length of its text). */
#include "timer.h"
#include <expat.h>

static long nel, nat;
static void XMLCALL s0(void *u, const XML_Char *n, const XML_Char **a) { nel++; for (; *a; a += 2) if (strncmp(*a, "xmlns", 5)) nat++; }
static void XMLCALL e0(void *u, const XML_Char *n) {}
static void XMLCALL c0(void *u, const XML_Char *s, int l) {}

typedef struct { char *name; long first_attr, n_attr, text_len; int parent; } node_t;
typedef struct { char *name, *value; } attr_t;
static node_t *nodes; static long nn, capn;
static attr_t *attrs; static long na, capa;
static char *text; static long nt, capt;
static int stack[4096], depth;
static char *dup(const char *s, size_t n) { char *p = malloc(n + 1); memcpy(p, s, n); p[n] = 0; return p; }
static void XMLCALL s1(void *u, const XML_Char *n, const XML_Char **a) {
    node_t *x;
    if (nn == capn) { capn = capn ? capn * 2 : 1024; nodes = realloc(nodes, capn * sizeof *nodes); }
    x = &nodes[nn]; x->name = dup(n, strlen(n)); x->parent = depth ? stack[depth - 1] : -1; x->first_attr = na; x->n_attr = 0; x->text_len = 0;
    for (; *a; a += 2) {
        if (na == capa) { capa = capa ? capa * 2 : 1024; attrs = realloc(attrs, capa * sizeof *attrs); }
        attrs[na].name = dup(a[0], strlen(a[0])); attrs[na].value = dup(a[1], strlen(a[1])); na++; x->n_attr++;
    }
    stack[depth++] = nn++;
}
static void XMLCALL e1(void *u, const XML_Char *n) { depth--; }
static void XMLCALL c1(void *u, const XML_Char *s, int l) {
    if (nt + l > capt) { capt = (nt + l) * 2; text = realloc(text, capt); }
    memcpy(text + nt, s, l); nt += l; nodes[stack[depth - 1]].text_len += l;
}

int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[argc - 1], &len);
    int copy = argc > 2 && !strcmp(argv[1], "copy");
    XML_Parser p = XML_ParserCreate(NULL);
    long i, el, at, tx, sink = 0;
    if (copy) { XML_SetElementHandler(p, s1, e1); XML_SetCharacterDataHandler(p, c1); }
    else { XML_SetElementHandler(p, s0, e0); XML_SetCharacterDataHandler(p, c0); }
    double t0 = now_ms();
    int ok = XML_Parse(p, buf, (int)len, 1) != XML_STATUS_ERROR;
    double t1 = now_ms();
    if (!ok) return report_xml(0, len, t0, t1, XML_ErrorString(XML_GetErrorCode(p)), 0, 0, 0);
    if (!copy) return report_xml(1, len, t0, t1, 0, nel, nat, -1);
    for (i = 0; i < nn; i++) sink += strlen(nodes[i].name) + nodes[i].parent + nodes[i].text_len + nodes[i].first_attr + nodes[i].n_attr;
    el = nn; at = 0;
    for (i = 0; i < na; i++) { sink += strlen(attrs[i].name) + strlen(attrs[i].value); at += !!strncmp(attrs[i].name, "xmlns", 5); }
    tx = nonblank(text, nt);
    if (sink < 0) return 3;
    return report_xml(1, len, t0, t1, 0, el, at, tx);
}
