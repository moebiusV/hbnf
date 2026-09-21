/* ------------------------------------------------------------------ */
/* Lexer: text -> token stream (schema-independent).  Skips whitespace */
/* and `#` comments; yields word/string/number/punctuation tokens.     */
/* ------------------------------------------------------------------ */

typedef struct { token_t *toks; size_t n; } lexed_t;

static int lex_digit(char c) { return c >= '0' && c <= '9'; }
static int lex_word_start(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || c == '_' || c == '-';
}
static int lex_word_char(char c) {
    return lex_word_start(c) || lex_digit(c) || c == '.';
}
static char *lex_dup(const char *s, size_t n) {
    char *p = (char *)malloc(n + 1);
    if (p) { memcpy(p, s, n); p[n] = '\0'; }
    return p;
}

lexed_t lex(const char *text) {
    lexed_t r = {0};
    token_t *toks = (token_t *)malloc((strlen(text) + 2) * sizeof *toks);
    size_t i = 0, line = 1, col = 1;

    while (text[i]) {
        char c = text[i];
        if (c == ' ' || c == '\t' || c == '\r') { i++; col++; }
        else if (c == '\n') { i++; line++; col = 1; }
        else if (c == '#') { while (text[i] && text[i] != '\n') i++; }
        else if (c == '"') {
            size_t sc = col;
            char *buf = (char *)malloc(strlen(text + i) + 1);
            size_t bn = 0;
            i++; col++;
            while (text[i] && text[i] != '"') {
                if (text[i] == '\\' && text[i + 1]) { i++; col++; }
                buf[bn++] = text[i++]; col++;
            }
            if (text[i] == '"') { i++; col++; }
            buf[bn] = '\0';
            toks[r.n++] = (token_t){ TOK_STR, buf, line, sc };
        }
        else if (lex_digit(c)) {
            size_t s = i, sc = col; int dec = 0;
            while (lex_digit(text[i])) { i++; col++; }
            if (text[i] == '.' && lex_digit(text[i + 1])) {
                dec = 1; i++; col++;
                while (lex_digit(text[i])) { i++; col++; }
            }
            if (text[i] == 'e' || text[i] == 'E') {
                dec = 1; i++; col++;
                if (text[i] == '+' || text[i] == '-') { i++; col++; }
                while (lex_digit(text[i])) { i++; col++; }
            }
            toks[r.n++] = (token_t){ dec ? TOK_DEC : TOK_INT,
                                     lex_dup(text + s, i - s), line, sc };
        }
        else if (lex_word_start(c)) {
            size_t s = i, sc = col;
            while (lex_word_char(text[i])) { i++; col++; }
            toks[r.n++] = (token_t){ TOK_ATOM, lex_dup(text + s, i - s), line, sc };
        }
        else {
            toks[r.n++] = (token_t){ TOK_PUNCT, lex_dup(text + i, 1), line, col };
            i++; col++;
        }
    }
    toks[r.n++] = (token_t){ TOK_EOF, lex_dup("", 0), line, col };
    r.toks = toks;
    return r;
}

/* Convenience: lex, split text into lines (for the caret), then parse. */
bool parse_text(const char *text, @ROOT_TYPE@ *out,
                char *err, size_t errlen, size_t *err_line, size_t *err_col) {
    lexed_t l = lex(text);
    size_t nlines = 1, i, k = 0, s = 0;
    const char *p;
    for (p = text; *p; p++) if (*p == '\n') nlines++;
    char **lines = (char **)malloc(nlines * sizeof *lines);
    for (i = 0; ; i++) {
        if (text[i] == '\n' || text[i] == '\0') {
            lines[k++] = lex_dup(text + s, i - s);
            if (text[i] == '\0') break;
            s = i + 1;
        }
    }
    bool ok = parse_tokens(l.toks, l.n, out, (const char *const *)lines, nlines,
                           err, errlen, err_line, err_col);
    for (i = 0; i < l.n; i++) free((char *)l.toks[i].text);
    free(l.toks);
    for (i = 0; i < nlines; i++) free(lines[i]);
    free(lines);
    return ok;
}
