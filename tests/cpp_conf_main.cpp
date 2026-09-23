// Include the generated C header from C++: wrap it in extern "C" so
// parse_config/conf_ptr keep C linkage and link against the C-compiled conf.c.
extern "C" {
#include "conf.h"
}

#include <cstdio>

int main() {
    if (parse_config("valid.conf") != 0) {
        std::puts("cpp: FAILED");
        return 1;
    }
    server_t *s = conf_ptr();
    std::printf("cpp: OK name=%s port=%u\n", s->name, (unsigned)s->listen.port);
    return 0;
}
