/* TinyXML-2, the small C++ DOM parser: XMLDocument::Parse (it copies the text it keeps), then a walk of the tree. */
#include "timer.h"
#include <tinyxml2.h>

static long nel, nat, ntx;
static void walk(const tinyxml2::XMLNode *n) {
    for (const tinyxml2::XMLNode *c = n->FirstChild(); c; c = c->NextSibling()) {
        if (const tinyxml2::XMLElement *e = c->ToElement()) {
            nel++;
            for (const tinyxml2::XMLAttribute *a = e->FirstAttribute(); a; a = a->Next()) nat += !!strncmp(a->Name(), "xmlns", 5);
            walk(c);
        } else if (c->ToText()) {
            const char *v = c->Value();
            ntx += nonblank(v, strlen(v));
        }
    }
}
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    tinyxml2::XMLDocument doc;
    double t0 = now_ms();
    tinyxml2::XMLError e = doc.Parse(buf, len);
    double t1 = now_ms();
    if (e != tinyxml2::XML_SUCCESS) return report_xml(0, len, t0, t1, doc.ErrorStr(), 0, 0, 0);
    walk(&doc);
    return report_xml(1, len, t0, t1, 0, nel, nat, ntx);
}
