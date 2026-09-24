const char *conf_file = NULL;

/* Default handler: print "file:line: <message>" to stderr and return, as
   parse.y's yyerror does; parse_config returns -1 once the parse is over.
   Override conf_error with your own to take the messages elsewhere. */
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
}
conf_error_fn conf_error = conf_error_default;

/* Every error, syntax or action, as it is found: conf_file names the
   file it is in (an included file while that one is read). */
static void conf_report(size_t line, const char *msg) {
    const char *top = conf_file;

    if (hbnf_file)
        conf_file = hbnf_file;
    conf_error(line, msg);
    conf_file = top;
}

/* The grammar's epilogue defines conf_init() to reset the conf's list heads
   (the action jets append to them, so they must be TAILQ_INIT'd first).
   The config is read one statement at a time: each is parsed, bound and
   freed, with its strings, before the next is read, so a jet copies
   whatever it keeps.  Every error is reported as it is found and the parse
   goes on, as parse.y's does; parse_config then returns -1. */
int parse_config(const char *filename, @CONF_TYPE@ *xconf) {
    char *buf;
    const char *why;
    char err[512];
    size_t line = 0, col = 0;
    bool ok;

    conf_file = filename;
    buf = hbnf_read_file(filename, &why);
    if (!buf) {
        conf_error(0, why);
        return -1;
    }
    conf = xconf;
    conf_init();
    bind_report = conf_report;
    hbnf_report = conf_report;
    ok = hbnf_stmts(buf, NULL, err, sizeof err, &line, &col);
    hbnf_report = NULL;
    bind_report = NULL;
    free(buf);
    return ok ? 0 : -1;
}
