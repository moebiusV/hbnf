#include "timer.h"
#include <libfyaml.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    double t0 = now_ms();
    struct fy_document *d = fy_document_build_from_string(NULL, buf, len);
    double t1 = now_ms();
    return report(d != NULL, len, t0, t1, "libfyaml refused it");
}
