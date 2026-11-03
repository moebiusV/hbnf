/* RapidXML 1.13 (Marcin Kalicinski; Debian's librapidxml-dev, the original, unmaintained since 2009): parse<0>
 * (parse_default) in place, then a walk of the tree. */
#include "timer.h"
#include <rapidxml/rapidxml.hpp>

static long nel, nat, ntx;
static void walk(const rapidxml::xml_node<> *n) {
    for (const rapidxml::xml_node<> *c = n->first_node(); c; c = c->next_sibling()) {
        if (c->type() == rapidxml::node_element) {
            nel++;
            for (const rapidxml::xml_attribute<> *a = c->first_attribute(); a; a = a->next_attribute()) nat += !!strncmp(a->name(), "xmlns", 5);
            walk(c);
        } else if (c->type() == rapidxml::node_data || c->type() == rapidxml::node_cdata) {
            ntx += nonblank(c->value(), c->value_size());
        }
    }
}
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    rapidxml::xml_document<> doc;
    const char *why = 0;
    double t0 = now_ms();
    try { doc.parse<0>(buf); } catch (rapidxml::parse_error &e) { why = e.what(); }
    double t1 = now_ms();
    if (why) return report_xml(0, len, t0, t1, why, 0, 0, 0);
    walk(&doc);
    return report_xml(1, len, t0, t1, 0, nel, nat, ntx);
}
