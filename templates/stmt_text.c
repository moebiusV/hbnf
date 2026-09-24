/* A string as a source of statements (parse_text's). */
static void hbnf_src_text(hbnf_src_t *s, const char *text) {
    memset(s, 0, sizeof *s);
    s->p = text;
    s->end = text + strlen(text);
}

/* Parse a whole config into *out (initialized here), one statement at a
   time.  err, *err_line and *err_col hold the first error (the parse goes
   on past it); false if there was any. */
bool parse_text(const char *text, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    hbnf_src_t src;
    bool ok;

    hbnf_part_init(out);
    hbnf_src_text(&src, text);
    ok = hbnf_stmts(&src, out, err, errlen, err_line, err_col);
    hbnf_src_done(&src);
    return ok;
}

/* The same for a file, read a block at a time rather than whole. */
bool parse_file(const char *path, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    hbnf_src_t src;
    FILE *f;
    bool ok;

    hbnf_part_init(out);
    if (!(f = fopen(path, "r"))) {
        snprintf(err, errlen, "cannot open file");
        *err_line = *err_col = 0;
        return false;
    }
    hbnf_src_file(&src, f);
    ok = hbnf_stmts(&src, out, err, errlen, err_line, err_col);
    hbnf_src_done(&src);
    fclose(f);
    return ok;
}
