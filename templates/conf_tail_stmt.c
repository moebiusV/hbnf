@ROOT_TYPE@ *conf = NULL;
const char *conf_file = NULL;

/* Default handler: print "file:line: <caret message>" and exit(1).  Override
   conf_error with your own to take the message elsewhere (then parse_config
   returns -1 after the handler). */
static void conf_error_default(size_t line, const char *msg) {
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
    exit(1);
}
conf_error_fn conf_error = conf_error_default;

/* The file is read a block at a time and parsed one statement at a time
   (parse_file); the tree is kept. */
int parse_config(const char *filename) {
    char err[512];
    size_t line = 0, col = 0;

    conf_file = filename;
    conf = (@ROOT_TYPE@ *)calloc(1, sizeof *conf);
    if (!conf) {
        conf_error(0, "out of memory");
        return -1;
    }
    if (!parse_file(filename, conf, err, sizeof err, &line, &col)) {
        conf_error(line, err);
        return -1;
    }
    return 0;
}

@ROOT_TYPE@ *conf_ptr(void) { return conf; }
