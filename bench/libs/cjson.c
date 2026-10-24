#include "timer.h"
#include <cjson/cJSON.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    double t0 = now_ms();
    cJSON *r = cJSON_ParseWithLength(buf, len);
    double t1 = now_ms();
    return report(r != NULL, len, t0, t1, "cJSON refused it");
}
