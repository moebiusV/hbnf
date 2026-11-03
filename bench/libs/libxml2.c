/* libxml2, the C library under lxml and xmllint.  Two modes, one process each: "dom" reads the document into its
 * xmlDoc tree (xmlReadMemory) and walks it; "sax" runs its SAX2 interface with handlers that count elements and
 * attributes and builds nothing. */
#include "timer.h"
#include <libxml/parser.h>
#include <libxml/tree.h>

static long nel, nat, ntx;
static void walk(xmlNode *n) {
    for (; n; n = n->next) {
        if (n->type == XML_ELEMENT_NODE) {
            xmlAttr *a;
            nel++;
            for (a = n->properties; a; a = a->next) nat++;
            walk(n->children);
        } else if (n->type == XML_TEXT_NODE || n->type == XML_CDATA_SECTION_NODE) {
            if (n->content) ntx += nonblank((const char *)n->content, strlen((const char *)n->content));
        }
    }
}
static void sax_start(void *ctx, const xmlChar *lname, const xmlChar *prefix, const xmlChar *uri, int nns, const xmlChar **ns,
                      int natt, int ndef, const xmlChar **atts) { nel++; nat += natt; }
static void sax_end(void *ctx, const xmlChar *lname, const xmlChar *prefix, const xmlChar *uri) {}
static void sax_chars(void *ctx, const xmlChar *ch, int len) {}

int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[argc - 1], &len);
    int sax = argc > 2 && !strcmp(argv[1], "sax"), ok;
    double t0, t1;
    xmlInitParser();
    if (sax) {
        xmlSAXHandler h;
        memset(&h, 0, sizeof h);
        h.initialized = XML_SAX2_MAGIC;
        h.startElementNs = sax_start; h.endElementNs = sax_end; h.characters = sax_chars; h.cdataBlock = sax_chars;
        t0 = now_ms();
        ok = xmlSAXUserParseMemory(&h, NULL, buf, (int)len) == 0;
        t1 = now_ms();
        return report_xml(ok, len, t0, t1, "libxml2 refused it", nel, nat, -1);
    }
    t0 = now_ms();
    xmlDoc *d = xmlReadMemory(buf, (int)len, "doc.xml", NULL, XML_PARSE_NONET);
    t1 = now_ms();
    if (!d) return report_xml(0, len, t0, t1, "libxml2 refused it", 0, 0, 0);
    walk(xmlDocGetRootElement(d));
    return report_xml(1, len, t0, t1, 0, nel, nat, ntx);
}
