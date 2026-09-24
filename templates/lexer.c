/* ------------------------------------------------------------------ */
/* Lexer: text -> token stream (schema-independent).  Skips whitespace */
/* and `#` comments; yields word/string/number/punctuation tokens.     */
/* ------------------------------------------------------------------ */

typedef struct { token_t *toks; size_t n; } lexed_t;

/* Append a token, growing the array geometrically.  Returns 0 when memory
   runs out; the lexer then gives up and its caller reports it. */
static int lex_push(lexed_t *r, size_t *cap, token_t t) {
    if (r->n == *cap) {
        size_t nc = *cap * 2;
        token_t *nt = (token_t *)realloc(r->toks, nc * sizeof *nt);
        if (!nt) return 0;
        r->toks = nt;
        *cap = nc;
    }
    r->toks[r->n++] = t;
    return 1;
}

static int lex_digit(char c) { return c >= '0' && c <= '9'; }
static int lex_word_start(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || c == '_' || c == '-'@WORD_CHARS@;
}
static int lex_word_char(char c) {
    return lex_word_start(c) || lex_digit(c) || c == '.';
}

/* The token array.  NULL toks (n = 0) means the input could not be
   lexed: it is over 4 GB (tokens hold 32-bit offsets) or memory ran out.
   Lines are counted from hbnf_line_base (a statement's first line). */
lexed_t lex(const char *text) {
    lexed_t r = {0};
    size_t i = 0, line = hbnf_line_base, col = 1;
    size_t tlen = strlen(text);
    /* A first guess of one token per 4 bytes of input (real configs run
       5-6): usually no regrowth, and a fraction of the old one-per-byte. */
    size_t cap = tlen / 4 + 16;

    if (tlen > (size_t)UINT32_MAX - 2) return r;
    r.toks = (token_t *)malloc(cap * sizeof *r.toks);
    if (!r.toks) return r;

    while (text[i]) {
        char c = text[i];
        {
            /* Hand-written jet scanners (schema `%{ %}` blocks) win first. */
            tok_kind_t jk;
            size_t jl = jet_dispatch(text, i, tlen, &jk);
            if (jl > 0) {
                if (!lex_push(&r, &cap, (token_t){ .text = text + i, .len = jl, .line = line, .col = col, .kind = jk, .kwid = KWID_NONE })) goto oom;
                i += jl; col += jl;
                continue;
            }
        }
        if (c == ' ' || c == '\t' || c == '\r') { i++; col++; }
        else if (c == '\n') { i++; line++; col = 1; }
        /* backslash-newline continues the line, as parse.y's lgetc() */
        else if (c == '\\' && text[i + 1] == '\n') { i += 2; line++; col = 1; }
        else if (c == '#') { while (text[i] && text[i] != '\n') i++; }
        else if (c == '"') {
            size_t sc = col, sl = line;
            i++; col++;
            while (text[i] && text[i] != '"') {
                /* inside quotes parse.y drops backslash-newline and a bare
                   newline alike, counting the line */
                if (text[i] == '\\' && text[i + 1] == '\n') { i += 2; line++; col = 1; continue; }
                if (text[i] == '\n') { i++; line++; col = 1; continue; }
                if (text[i] == '\\' && text[i + 1]) { i++; col++; }
                hbnf_str_put(text[i++]); col++;
            }
            if (text[i] == '"') { i++; col++; }
            { size_t n = hbnf_scratch_len;
              const char *s = hbnf_str_append(hbnf_scratch, n);
              hbnf_scratch_len = 0;
              if (!lex_push(&r, &cap, (token_t){ .text = s, .len = n, .line = sl, .col = sc, .kind = TOK_STR, .kwid = KWID_NONE })) goto oom; }
        }
        else if (lex_digit(c) || (c == '-' && lex_digit(text[i + 1]))) {
            /* -N is a number too, as in parse.y's lexers */
            size_t s = i, sc = col;
            if (c == '-') { i++; col++; }
            while (lex_digit(text[i])) { i++; col++; }
            if (lex_word_char(text[i])) {
                /* dotted/alphanumeric run (1.2.3.4, 123abc) is one word */
                i = s; col = sc;
                while (lex_word_char(text[i])) { i++; col++; }
                if (!lex_push(&r, &cap, (token_t){ .text = text + s, .len = i - s, .line = line, .col = sc, .kind = TOK_ATOM, .kwid = kw_lookup(text + s, i - s) })) goto oom;
            } else {
                if (!lex_push(&r, &cap, (token_t){ .text = text + s, .len = i - s, .line = line, .col = sc, .kind = TOK_INT, .kwid = KWID_NONE })) goto oom;
            }
        }
        else if (lex_word_start(c)) {
            size_t s = i, sc = col;
            while (lex_word_char(text[i])) { i++; col++; }
            if (!lex_push(&r, &cap, (token_t){ .text = text + s, .len = i - s, .line = line, .col = sc, .kind = TOK_ATOM, .kwid = kw_lookup(text + s, i - s) })) goto oom;
        }
        else {
            if (!lex_push(&r, &cap, (token_t){ .text = text + i, .len = 1, .line = line, .col = col, .kind = TOK_PUNCT, .kwid = KWID_NONE })) goto oom;
            i++; col++;
        }
    }
    if (!lex_push(&r, &cap, (token_t){ .text = "", .len = 0, .line = line, .col = col, .kind = TOK_EOF, .kwid = KWID_NONE })) goto oom;
    return r;
oom:
    free(r.toks);
    r.toks = NULL;
    r.n = 0;
    return r;
}
