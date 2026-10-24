#include "timer.h"
#include <yaml-cpp/yaml.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    std::string s(buf, len);
    double t0, t1;
    try {
        t0 = now_ms();
        YAML::Node n = YAML::Load(s);
        t1 = now_ms();
        return report(1, len, t0, t1, 0);
    } catch (const std::exception &e) { return report(0, len, 0, 0, e.what()); }
}
