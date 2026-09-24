/* tests/stmt.sh's driver: `-Dname=value` sets a macro, anything else is a
   config to parse_config; prints what the actions counted. */
#include <stdio.h>
#include <string.h>
#include "conf.h"

struct count_conf { int prefs; int forwarders; };

/* Every error, in order with the counts (stdout). */
static void report(size_t line, const char *msg) {
    printf("  %s:%zu: %s\n", conf_file, line, msg);
}

int main(int argc, char **argv) {
    struct count_conf c;
    int i;

    conf_error = report;
    for (i = 1; i < argc; i++) {
        if (strncmp(argv[i], "-D", 2) == 0) {
            printf("-D%s: %d\n", argv[i] + 2, cmdline_symset(argv[i] + 2));
            continue;
        }
        printf("%s:\n", argv[i]);
        printf("  parse_config = %d", parse_config(argv[i], &c));
        printf(", preferences=%d forwarders=%d\n", c.prefs, c.forwarders);
    }
    return 0;
}
