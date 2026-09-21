@ROOT_TYPE@ *conf = NULL;

/* Default handler: print "file:line: <caret message>" and exit(1).  Override
   conf_error with your own to take the message elsewhere (then parse_config
   returns -1 after calling it). */
static void conf_error_default(const char *file, size_t line, const char *msg) {
    if (line)
        fprintf(stderr, "%s:%zu: %s\n", file, line, msg);
    else
        fprintf(stderr, "%s: %s\n", file, msg);
    exit(1);
}

conf_error_fn conf_error = conf_error_default;

int parse_config(const char *filename) {
    FILE *f = fopen(filename, "r");
    char *buf;
    long len;
    char err[512];
    size_t line = 0, col = 0;

    if (!f) {
        conf_error(filename, 0, "cannot open file");
        return -1;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (len = ftell(f)) < 0 ||
        fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        conf_error(filename, 0, "cannot read file");
        return -1;
    }
    buf = (char *)malloc((size_t)len + 1);
    if (!buf) {
        fclose(f);
        conf_error(filename, 0, "out of memory");
        return -1;
    }
    if (len > 0 && fread(buf, 1, (size_t)len, f) != (size_t)len) {
        free(buf);
        fclose(f);
        conf_error(filename, 0, "read error");
        return -1;
    }
    buf[len] = '\0';
    fclose(f);

    conf = (@ROOT_TYPE@ *)calloc(1, sizeof *conf);
    if (!conf) {
        free(buf);
        conf_error(filename, 0, "out of memory");
        return -1;
    }
    if (!parse_text(buf, conf, err, sizeof err, &line, &col)) {
        free(buf);
        conf_error(filename, line, err);  /* err carries the caret message */
        return -1;
    }
    free(buf);
    return 0;
}
