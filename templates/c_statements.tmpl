/* ------------------------------------------------------------------ */
/* Statements (the grammar's `statements` directive): the config is    */
/* read one statement at a time, as parse.y's yyparse reads it.  A     */
/* statement ends at a newline outside braces, quotes and comments;    */
/* backslash-newline continues it, and so does a next line that starts */
/* with `{`.  A file is read in blocks, not whole.  Each statement is  */
/* expanded (macros), lexed, parsed, bound and then appended to the    */
/* caller's list, or dropped once the action jets have taken what they */
/* keep, so only one statement's text, tokens (and nodes) are held at  */
/* a time.  A failed statement is reported and the parse goes on with  */
/* the next one, as parse.y's error rule does.                         */
/* ------------------------------------------------------------------ */

/* Each error as it is found (parse_config points it at conf_error), and
   the file being read: NULL for the top file, else the included one. */
static void (*hbnf_report)(size_t line, const char *msg);
static const char *hbnf_file;

/* Macro hooks: macros.c, or stubs for a grammar without `macros`. */
static char *hbnf_expand(const char *s, size_t len, char *msg, size_t msglen);
static void hbnf_trail(char *msg, size_t msglen, size_t line, size_t col);
static void hbnf_define(const token_t *toks, size_t n, size_t line);
static void hbnf_macros_done(void);

static char *hbnf_strndup(const char *s, size_t n) {
    char *d = (char *)malloc(n + 1);

    if (!d)
        hbnf_oom();
    memcpy(d, s, n);
    d[n] = '\0';
    return d;
}

typedef struct {
    @ROOT_TYPE@ *out;          /* the caller's list; NULL: keep nothing */
    char *err;                 /* the first error, for the caller */
    size_t errlen;
    size_t *err_line, *err_col;
    size_t errors;
    size_t top_line;           /* the top file's current statement */
} hbnf_run_t;

/* Count an error, report it unless an action jet already has, and keep
   the first for the caller: in an included file, as "file:line: msg" on
   the line of the top file's include. */
static void hbnf_error(hbnf_run_t *r, size_t line, size_t col,
                       const char *msg, int reported) {
    r->errors++;
    if (!reported && hbnf_report)
        hbnf_report(line, msg);
    if (r->errors > 1)
        return;
    if (hbnf_file) {
        snprintf(r->err, r->errlen, "%s:%zu: %s", hbnf_file, line, msg);
        *r->err_line = r->top_line;
        *r->err_col = 0;
    } else {
        snprintf(r->err, r->errlen, "%s", msg);
        *r->err_line = line;
        *r->err_col = col;
    }
}

/* Where statements come from: a file, read a block at a time, or a
   string.  Characters read ahead and not used are given back. */
enum { HBNF_BLOCK = 65536 };

typedef struct {
    FILE *f;                   /* the file, or NULL for a string */
    const char *p, *end;       /* the unread part of the block (or string) */
    char *blk;                 /* the block, for a file */
    char *back;                /* given back, last in first out */
    size_t nback, capback;
    int err;                   /* the file could not be read */
} hbnf_src_t;

static void hbnf_src_file(hbnf_src_t *s, FILE *f) {
    memset(s, 0, sizeof *s);
    s->f = f;
    s->blk = (char *)malloc(HBNF_BLOCK);
    if (!s->blk)
        hbnf_oom();
}

static void hbnf_src_done(hbnf_src_t *s) {
    free(s->blk);
    free(s->back);
}

static int hbnf_getc(hbnf_src_t *s) {
    if (s->nback)
        return (unsigned char)s->back[--s->nback];
    if (s->p == s->end) {
        size_t n;
        if (!s->f)
            return EOF;
        n = fread(s->blk, 1, HBNF_BLOCK, s->f);
        if (n == 0) {
            if (ferror(s->f))
                s->err = 1;
            return EOF;
        }
        s->p = s->blk;
        s->end = s->blk + n;
    }
    return (unsigned char)*s->p++;
}

static void hbnf_ungetc(hbnf_src_t *s, int c) {
    if (c == EOF)
        return;
    if (s->nback == s->capback) {
        size_t nc = s->capback ? s->capback * 2 : 64;
        char *nb = (char *)realloc(s->back, nc);
        if (!nb)
            hbnf_oom();
        s->back = nb;
        s->capback = nc;
    }
    s->back[s->nback++] = (char)c;
}

/* One statement's text, reused from statement to statement. */
typedef struct {
    char *s;
    size_t len, cap;
} hbnf_buf_t;

static void hbnf_buf_grow(hbnf_buf_t *b, size_t n) {
    if (b->len + n + 1 > b->cap) {
        size_t nc = b->cap ? b->cap * 2 : 256;
        char *ns;
        while (nc < b->len + n + 1)
            nc *= 2;
        if (!(ns = (char *)realloc(b->s, nc)))
            hbnf_oom();
        b->s = ns;
        b->cap = nc;
    }
}

static void hbnf_buf_put(hbnf_buf_t *b, int c) {
    hbnf_buf_grow(b, 1);
    b->s[b->len++] = (char)c;
}

enum { HBNF_NO_MORE, HBNF_AT_NEWLINE, HBNF_AT_END };

/* Read the next statement into b, NUL-terminated: up to the newline that
   ends it, which is read and not kept.  *nl counts the newlines inside
   it; *empty is set when it holds only blanks and comments.  Quotes and
   comments are read as the lexer reads them, so a brace in either does
   not count.  Returns what ended it: a newline, the end of the input, or
   HBNF_NO_MORE when there was nothing left to read. */
static int hbnf_read_stmt(hbnf_src_t *s, hbnf_buf_t *b, size_t *nl,
                          int *empty) {
    long depth = 0;
    int c, any = 0;

    b->len = 0;
    *nl = 0;
    *empty = 1;
    for (;;) {
        if (!s->nback && s->p < s->end) {
            /* a run of characters that need no care, copied at once */
            const char *q = s->p;
            while (q < s->end && *q != '\n' && *q != '\\' && *q != '#'
                   && *q != '"' && *q != '{' && *q != '}') {
                if (*q != ' ' && *q != '\t' && *q != '\r')
                    *empty = 0;
                q++;
            }
            if (q > s->p) {
                hbnf_buf_grow(b, (size_t)(q - s->p));
                memcpy(b->s + b->len, s->p, (size_t)(q - s->p));
                b->len += (size_t)(q - s->p);
                s->p = q;
                any = 1;
                continue;
            }
        }
        c = hbnf_getc(s);
        if (c == EOF)
            break;
        any = 1;
        if (c == '\n') {
            if (depth <= 0) {
                /* a `{` opening the next line continues this statement;
                   anything else there starts the next one */
                size_t keep = b->len;
                int d;
                if (*empty)
                    goto at_newline;
                hbnf_buf_put(b, '\n');
                while ((d = hbnf_getc(s)) == ' ' || d == '\t' || d == '\r')
                    hbnf_buf_put(b, d);
                hbnf_ungetc(s, d);
                if (d != '{') {
                    while (b->len > keep + 1)
                        hbnf_ungetc(s, (unsigned char)b->s[--b->len]);
                    b->len = keep;
                    goto at_newline;
                }
                (*nl)++;
                continue;
            }
            (*nl)++;
            hbnf_buf_put(b, c);
        } else if (c == '\\') {
            int d = hbnf_getc(s);
            hbnf_buf_put(b, c);
            if (d == '\n') {
                (*nl)++;
                hbnf_buf_put(b, d);
            } else {
                *empty = 0;
                hbnf_ungetc(s, d);
            }
        } else if (c == '#') {
            do
                hbnf_buf_put(b, c);
            while ((c = hbnf_getc(s)) != EOF && c != '\n');
            hbnf_ungetc(s, c);
        } else if (c == ' ' || c == '\t' || c == '\r') {
            hbnf_buf_put(b, c);
        } else if (c == '"') {
            *empty = 0;
            hbnf_buf_put(b, c);
            while ((c = hbnf_getc(s)) != EOF) {
                hbnf_buf_put(b, c);
                if (c == '"')
                    break;
                if (c == '\\') {
                    if ((c = hbnf_getc(s)) == EOF)
                        break;
                    hbnf_buf_put(b, c);
                }
                if (c == '\n')
                    (*nl)++;
            }
        } else {
            *empty = 0;
            if (c == '{')
                depth++;
            else if (c == '}')
                depth--;
            hbnf_buf_put(b, c);
        }
    }
    hbnf_buf_put(b, '\0');
    b->len--;
    return any ? HBNF_AT_END : HBNF_NO_MORE;
at_newline:
    hbnf_buf_put(b, '\0');
    b->len--;
    return HBNF_AT_NEWLINE;
}

static void hbnf_run(hbnf_run_t *r, hbnf_src_t *src, int depth);

/* An `include`: read the file's statements in its place. */
static void hbnf_include(hbnf_run_t *r, const char *path, size_t line,
                         int depth) {
    char msg[512];
    const char *outer = hbnf_file;
    hbnf_src_t src;
    FILE *f;

    if (depth >= 16) {
        snprintf(msg, sizeof msg, "%s: includes nested too deeply", path);
        hbnf_error(r, line, 0, msg, 0);
        return;
    }
    if (!(f = fopen(path, "r"))) {
        snprintf(msg, sizeof msg, "failed to include file %s", path);
        hbnf_error(r, line, 0, msg, 0);
        return;
    }
    hbnf_src_file(&src, f);
    hbnf_file = path;
    hbnf_run(r, &src, depth + 1);
    hbnf_file = outer;
    hbnf_src_done(&src);
    fclose(f);
}

/* One statement, s[0..len), which starts on line `line` of its file. */
static void hbnf_stmt(hbnf_run_t *r, const char *s, size_t len, size_t line,
                      int depth) {
    char msg[512];
    char *buf, *inc = NULL;
    lexed_t l;
    @ROOT_TYPE@ part;
    size_t el = 0, ec = 0;
    bool ok;

    buf = hbnf_expand(s, len, msg, sizeof msg);
    if (!buf) {
        hbnf_error(r, line, 0, msg, 0);
        return;
    }
    hbnf_line_base = line;
    l = lex(buf);
    if (!l.toks) {
        hbnf_line_base = 1;
        free(buf);
        hbnf_error(r, line, 0, len > (size_t)UINT32_MAX - 2
                   ? "input too large" : "out of memory", 0);
        return;
    }
    hbnf_part_init(&part);
    ok = parse_tokens(l.toks, l.n, &part, buf, msg, sizeof msg, &el, &ec);
    hbnf_line_base = 1;
    if (ok) {
        const token_t *t = hbnf_include_tok(l.toks, l.n);
        hbnf_define(l.toks, l.n, line);
        if (t)
            inc = hbnf_strndup(t->text, t->len);
    } else {
        if (el < line)
            el = line;
        hbnf_trail(msg, sizeof msg, el - line, ec);
        hbnf_error(r, el, ec, msg, hbnf_bind_reported());
    }
    if (!r->out)
        hbnf_part_free(&part);       /* the nodes and the string arena */
    else if (ok)
        hbnf_part_move(r->out, &part);
    else
        hbnf_part_drop(&part);
    free(l.toks);
    free(buf);
    if (inc) {
        hbnf_include(r, inc, line, depth);
        free(inc);
    }
}

/* Every statement of one file (or string). */
static void hbnf_run(hbnf_run_t *r, hbnf_src_t *src, int depth) {
    hbnf_buf_t b;
    size_t line = 1, nl;
    int empty, end;

    memset(&b, 0, sizeof b);
    while ((end = hbnf_read_stmt(src, &b, &nl, &empty)) != HBNF_NO_MORE) {
        if (!empty) {
            if (!depth)
                r->top_line = line;
            hbnf_stmt(r, b.s, b.len, line, depth);
        }
        line += nl;
        if (end == HBNF_AT_END)
            break;
        line++;
    }
    free(b.s);
    if (src->err)
        hbnf_error(r, line, 0, "read error", 0);
}

/* Read a config: each statement is appended to *out, or with out NULL
   dropped once bound.  err, *err_line and *err_col hold the first error;
   false if there was any. */
static bool hbnf_stmts(hbnf_src_t *src, @ROOT_TYPE@ *out,
                       char *err, size_t errlen,
                       size_t *err_line, size_t *err_col) {
    hbnf_run_t r;

    memset(&r, 0, sizeof r);
    r.out = out;
    r.err = err;
    r.errlen = errlen;
    r.err_line = err_line;
    r.err_col = err_col;
    if (errlen)
        err[0] = '\0';
    *err_line = *err_col = 0;
    hbnf_file = NULL;
    hbnf_run(&r, src, 0);
    hbnf_macros_done();
    return r.errors == 0;
}
