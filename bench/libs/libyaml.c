/* libyaml's document API: the first document is loaded into a node tree. */
#include "timer.h"
#include <yaml.h>
int main(int argc, char **argv) {
    long len; char *buf = read_file(argv[1], &len);
    yaml_parser_t p; yaml_document_t d;
    yaml_parser_initialize(&p);
    yaml_parser_set_input_string(&p, (const unsigned char *)buf, len);
    double t0 = now_ms();
    int ok = yaml_parser_load(&p, &d);
    double t1 = now_ms();
    return report(ok, len, t0, t1, p.problem);
}
