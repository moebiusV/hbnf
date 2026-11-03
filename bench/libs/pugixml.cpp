/* pugixml, the C++ DOM parser: load_buffer_inplace (what its documentation recommends for speed: it parses the
 * buffer where it lies and does not copy it), then a walk of the tree. */
#include "timer.h"
#include <pugixml.hpp>

static long nel, nat, ntx;
static void walk(pugi::xml_node n) {
    for (pugi::xml_node c = n.first_child(); c; c = c.next_sibling()) {
        if (c.type() == pugi::node_element) {
            nel++;
            for (pugi::xml_attribute a = c.first_attribute(); a; a = a.next_attribute()) nat += !!strncmp(a.name(), "xmlns", 5);
            walk(c);
        } else if (c.type() == pugi::node_pcdata || c.type() == pugi::node_cdata) {
            const char *v = c.value();
            ntx += nonblank(v, strlen(v));
        }
    }
}
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    pugi::xml_document doc;
    double t0 = now_ms();
    pugi::xml_parse_result r = doc.load_buffer_inplace(buf, len);
    double t1 = now_ms();
    if (!r) return report_xml(0, len, t0, t1, r.description(), 0, 0, 0);
    walk(doc);
    return report_xml(1, len, t0, t1, 0, nel, nat, ntx);
}
