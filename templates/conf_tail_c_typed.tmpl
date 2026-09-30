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

/* The grammar's epilogue defines conf_init() to reset the conf's list heads
   (the action jets append to them, so they must be TAILQ_INIT'd first).
   The parse tree is only the action jets' input: it is freed, with the
   string arena, before parse_config returns, so a jet copies whatever it
   keeps. */
int @ENTRY@(const char *filename, @CONF_TYPE@ *xconf) {
    FILE *f = fopen(filename, "r");
    char *buf;
    long len;
    char err[512];
    size_t line = 0, col = 0;

    if (!f) {
        conf_error(0, "cannot open file");
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (len = ftell(f)) < 0 ||
        fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        conf_error(0, "cannot read file");
        return -1;
    }
    buf = (char *)malloc((size_t)len + 1);
    if (!buf) {
        fclose(f);
        conf_error(0, "out of memory");
        return -1;
    }
    if (len > 0 && fread(buf, 1, (size_t)len, f) != (size_t)len) {
        free(buf);
        fclose(f);
        conf_error(0, "read error");
        return -1;
    }
    buf[len] = '\0';
    fclose(f);

    conf_file = filename;
    conf = xconf;
    conf_init();
    {
        @ROOT_TYPE@ ast;
        bool ok;
        memset(&ast, 0, sizeof ast);
        bind_errors = 0;
        bind_report = conf_error;   /* every action error, as it happens */
        ok = parse_text(buf, &ast, err, sizeof err, &line, &col);
        bind_report = NULL;
        free_@ROOT_C@(&ast);        /* the tree and the string arena */
        free(buf);
        if (!ok) {
            if (!bind_errors)      /* a syntax error: not reported yet */
                conf_error(line, err);
            return -1;
        }
    }
    return 0;
}
