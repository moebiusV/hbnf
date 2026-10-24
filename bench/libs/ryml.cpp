#define RYML_SINGLE_HDR_DEFINE_NOW
#include "ryml.hpp"
#include "timer.h"
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    ryml::csubstr src(buf, len);
    double t0 = now_ms();
    ryml::Tree t = ryml::parse_in_arena(src);
    double t1 = now_ms();
    return report(1, len, t0, t1, 0);
}
