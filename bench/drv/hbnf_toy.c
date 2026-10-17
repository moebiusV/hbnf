/* hbnf_toy.c — time hbnf's generated parse_text over the toy file.
 * parser.c is the generated parser (concatenated or -I'd by the stage). */
#include "timing.h"
#include "parser.c"

int main(int argc, char **argv) {
    size_t len, l = 0, c = 0;
    char *buf;
    struct config_list out;
    char err[512];
    double t0, ms;
    int ok;
    long count = 0;
    long long sum = 0;
    struct config_s *e;

    if (argc < 2) return 2;
    buf = bench_read(argv[1], &len);
    t0 = bench_now_ms();
    ok = parse_text(buf, &out, err, sizeof err, &l, &c);
    ms = bench_now_ms() - t0;
    if (ok)
        for (e = out.head; e; e = e->_link) {
            count++;
            sum += e->rule.from.int_ + e->rule.to.int_;
        }
    return bench_report(ok, len, count, sum, ms);
}
