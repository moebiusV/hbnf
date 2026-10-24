// The DOM API: the whole document is parsed into a tape before the call returns.
#include "timer.h"
#include <simdjson.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    simdjson::padded_string ps(buf, len);
    simdjson::dom::parser parser;
    simdjson::dom::element e;
    double t0 = now_ms();
    auto err = parser.parse(ps).get(e);
    double t1 = now_ms();
    return report(!err, len, t0, t1, "simdjson refused it");
}
