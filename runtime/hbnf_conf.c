/* hbnf_conf.c -- the parts of hbnf_conf.h that do not depend on the grammar. */
#include <stdio.h>
#include <stdlib.h>
#include "hbnf_conf.h"

const char *conf_file = NULL;

void conf_error_default(size_t line, const char *msg) {
    {   /* a message that begins with its own line:column:offset: is printed as file:that */
        size_t l_, c_, o_;
        int n_ = 0;
        if (sscanf(msg, "%zu:%zu:%zu: %n", &l_, &c_, &o_, &n_) >= 3 && n_ > 0) {
            if (conf_file)
                fprintf(stderr, "%s:%s\n", conf_file, msg);
            else
                fprintf(stderr, "%s\n", msg);
            exit(1);
        }
    }
    if (conf_file) {
        if (line)
            fprintf(stderr, "%s:%zu: %s\n", conf_file, line, msg);
        else
            fprintf(stderr, "%s: %s\n", conf_file, msg);
    } else {
        if (line)
            fprintf(stderr, "%zu: %s\n", line, msg);
        else
            fprintf(stderr, "%s\n", msg);
    }
}

conf_error_fn conf_error = conf_error_default;
