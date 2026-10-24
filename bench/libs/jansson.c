#include "timer.h"
#include <jansson.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    json_error_t e;
    double t0 = now_ms();
    json_t *r = json_loadb(buf, len, 0, &e);
    double t1 = now_ms();
    return report(r != NULL, len, t0, t1, e.text);
}
