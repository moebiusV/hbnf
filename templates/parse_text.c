/* Convenience: lex, then parse (the caret line is drawn lazily on error). */
bool parse_text(const char *text, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    lexed_t l = lex(text);
    if (!l.toks) {
        snprintf(err, errlen, "%s", strlen(text) > (size_t)UINT32_MAX - 2
                 ? "input too large" : "out of memory");
        *err_line = *err_col = 0;
        return false;
    }
    bool ok = parse_tokens(l.toks, l.n, out, text,
                           err, errlen, err_line, err_col);
    free(l.toks);
    return ok;
}
