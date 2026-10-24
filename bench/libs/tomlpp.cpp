#include "timer.h"
#include <toml++/toml.hpp>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    std::string_view sv(buf, len);
    double t0, t1;
    try {
        t0 = now_ms();
        auto t = toml::parse(sv);
        t1 = now_ms();
        return report(1, len, t0, t1, 0);
    } catch (const std::exception &e) { return report(0, len, 0, 0, e.what()); }
}
