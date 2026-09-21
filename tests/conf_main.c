#include <stdio.h>
#include <string.h>
#include "conf.h"

/* Non-exiting error handler: capture the caret message, let parse_config
   return -1 instead of exit(1). */
static void my_error(size_t line, const char *msg) {
    printf("callback: file=%s line=%zu msg=\n%s\n", conf_file, line, msg);
}

int main(void) {
    if (parse_config("valid.conf") != 0) {
        printf("valid: FAILED\n");
        return 1;
    }
    printf("valid: OK name=%s port=%u\n", conf->name, (unsigned)conf->listen.port);

    conf_error = my_error;
    if (parse_config("bad.conf") != -1) {
        printf("bad: expected -1, got success\n");
        return 1;
    }
    printf("bad: handled by callback (returned -1)\n");
    return 0;
}
