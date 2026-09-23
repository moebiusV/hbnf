/* ------------------------------------------------------------------ */
/* Lexer: text -> token stream (schema-independent).  Skips whitespace */
/* and `#` comments; yields word/string/number/punctuation tokens.     */
/* ------------------------------------------------------------------ */

typedef struct { token_t *toks; size_t n; } lexed_t;

static int lex_digit(char c) { return c >= '0' && c <= '9'; }
static int lex_word_start(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || c == '_' || c == '-'@WORD_CHARS@;
}
static int lex_word_char(char c) {
    return lex_word_start(c) || lex_digit(c) || c == '.';
}

lexed_t lex(const char *text) {
    lexed_t r = {0};
    token_t *toks = (token_t *)malloc((strlen(text) + 2) * sizeof *toks);
    size_t i = 0, line = 1, col = 1;
    size_t tlen = strlen(text);

    while (text[i]) {
        char c = text[i];
        {
            /* Hand-written jet scanners (schema `%{ %}` blocks) win first. */
            tok_kind_t jk;
            size_t jl = jet_dispatch(text, i, tlen, &jk);
            if (jl > 0) {
                toks[r.n++] = (token_t){ jk, text + i, jl, KWID_NONE, line, col };
                i += jl; col += jl;
                continue;
            }
        }
        if (c == ' ' || c == '\t' || c == '\r') { i++; col++; }
        else if (c == '\n') { i++; line++; col = 1; }
        else if (c == '#') { while (text[i] && text[i] != '\n') i++; }
        else if (c == '"') {
            size_t sc = col;
            i++; col++;
            while (text[i] && text[i] != '"') {
                if (text[i] == '\\' && text[i + 1]) { i++; col++; }
                hbnf_str_put(text[i++]); col++;
            }
            if (text[i] == '"') { i++; col++; }
            { size_t n = hbnf_scratch_len;
              const char *s = hbnf_str_append(hbnf_scratch, n);
              hbnf_scratch_len = 0;
              toks[r.n++] = (token_t){ TOK_STR, s, n, KWID_NONE, line, sc }; }
        }
        else if (lex_digit(c)) {
            size_t s = i, sc = col;
            while (lex_digit(text[i])) { i++; col++; }
            if (lex_word_char(text[i])) {
                /* dotted/alphanumeric run (1.2.3.4, 123abc) is one word */
                i = s; col = sc;
                while (lex_word_char(text[i])) { i++; col++; }
                toks[r.n++] = (token_t){ TOK_ATOM, text + s, i - s, kw_lookup(text + s, i - s), line, sc };
            } else {
                toks[r.n++] = (token_t){ TOK_INT, text + s, i - s, KWID_NONE, line, sc };
            }
        }
        else if (lex_word_start(c)) {
            size_t s = i, sc = col;
            while (lex_word_char(text[i])) { i++; col++; }
            toks[r.n++] = (token_t){ TOK_ATOM, text + s, i - s, kw_lookup(text + s, i - s), line, sc };
        }
        else {
            toks[r.n++] = (token_t){ TOK_PUNCT, text + i, 1, KWID_NONE, line, col };
            i++; col++;
        }
    }
    toks[r.n++] = (token_t){ TOK_EOF, "", 0, KWID_NONE, line, col };
    r.toks = toks;
    return r;
}

/* Convenience: lex, then parse (the caret line is drawn lazily on error). */
bool parse_text(const char *text, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    lexed_t l = lex(text);
    bool ok = parse_tokens(l.toks, l.n, out, text,
                           err, errlen, err_line, err_col);
    free(l.toks);
    return ok;
}
