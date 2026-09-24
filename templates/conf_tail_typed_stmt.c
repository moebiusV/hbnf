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
   The file is read a block at a time and parsed one statement at a time:
   each statement is parsed, bound and freed, with its strings, before the
   next is read, so a jet copies whatever it keeps.  Every error is
   reported as it is found and the parse goes on, as parse.y's does;
   parse_config then returns -1. */
int parse_config(const char *filename, @CONF_TYPE@ *xconf) {
    FILE *f;
    hbnf_src_t src;
    char err[512];
    size_t line = 0, col = 0;
    bool ok;

    conf_file = filename;
    if (!(f = fopen(filename, "r"))) {
        conf_error(0, "cannot open file");
        return -1;
    }
    conf = xconf;
    conf_init();
    bind_report = conf_report;
    hbnf_report = conf_report;
    hbnf_src_file(&src, f);
    ok = hbnf_stmts(&src, NULL, err, sizeof err, &line, &col);
    hbnf_src_done(&src);
    hbnf_report = NULL;
    bind_report = NULL;
    fclose(f);
    return ok ? 0 : -1;
}
