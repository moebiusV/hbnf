/* Parse a whole config into *out (initialized here), one statement at a
   time.  err, *err_line and *err_col hold the first error (the parse goes
   on past it); false if there was any. */
bool parse_text(const char *text, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    hbnf_part_init(out);
    return hbnf_stmts(text, out, err, errlen, err_line, err_col);
}
