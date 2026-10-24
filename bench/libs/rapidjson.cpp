#include "timer.h"
#include <rapidjson/document.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    rapidjson::Document d;
    double t0 = now_ms();
    d.Parse(buf, len);
    double t1 = now_ms();
    return report(!d.HasParseError(), len, t0, t1, "RapidJSON refused it");
}
