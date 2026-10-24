#include "timer.h"
#include "tomlc17.h"
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    double t0 = now_ms();
    toml_result_t r = toml_parse(buf, (int)len);
    double t1 = now_ms();
    return report(r.ok, len, t0, t1, r.errmsg);
}
