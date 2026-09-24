/* ------------------------------------------------------------------ */
/* Statements (the grammar's `statements` directive): the config is    */
/* read one statement at a time, as parse.y's yyparse reads it.  A     */
/* statement ends at a newline outside braces, quotes and comments;    */
/* backslash-newline continues it, and so does a next line that starts */
/* with `{`.  Each statement is expanded (macros), lexed, parsed, bound */
/* and then appended to the caller's list, or dropped once the action  */
/* jets have taken what they keep, so only one statement's tokens (and */
/* nodes) are held at a time.  A failed statement is reported and the  */
/* parse goes on with the next one, as parse.y's error rule does.      */
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

/* A whole file, NUL-terminated; NULL, with *why, if it cannot be read. */
static char *hbnf_read_file(const char *path, const char **why) {
    FILE *f = fopen(path, "r");
    char *buf;
    long len;

    if (!f) {
        *why = "cannot open file";
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0 || (len = ftell(f)) < 0 ||
        fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        *why = "cannot read file";
        return NULL;
    }
    buf = (char *)malloc((size_t)len + 1);
    if (!buf) {
        fclose(f);
        *why = "out of memory";
        return NULL;
    }
    if (len > 0 && fread(buf, 1, (size_t)len, f) != (size_t)len) {
        free(buf);
        fclose(f);
        *why = "read error";
        return NULL;
    }
    buf[len] = '\0';
    fclose(f);
    return buf;
}

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

/* The end of the statement at s[i]: the newline that ends it, or the NUL.
   *nl counts the newlines inside it; *empty is set when it holds only
   blanks and comments.  Quotes and comments are skipped as the lexer
   skips them, so a brace in either does not count. */
static size_t hbnf_stmt_end(const char *s, size_t i, size_t *nl, int *empty) {
    long depth = 0;

    *nl = 0;
    *empty = 1;
    for (;;) {
        char c = s[i];
        if (!c)
            return i;
        if (c == '\n') {
            if (depth <= 0) {
                size_t j = i + 1;
                while (s[j] == ' ' || s[j] == '\t' || s[j] == '\r')
                    j++;
                if (*empty || s[j] != '{')
                    return i;
            }
            (*nl)++;
            i++;
        } else if (c == '\\' && s[i + 1] == '\n') {
            (*nl)++;
            i += 2;
        } else if (c == '#') {
            while (s[i] && s[i] != '\n')
                i++;
        } else if (c == ' ' || c == '\t' || c == '\r') {
            i++;
        } else if (c == '"') {
            *empty = 0;
            i++;
            while (s[i] && s[i] != '"') {
                if (s[i] == '\\' && s[i + 1]) {
                    if (s[i + 1] == '\n')
                        (*nl)++;
                    i += 2;
                    continue;
                }
                if (s[i] == '\n')
                    (*nl)++;
                i++;
            }
            if (s[i])
                i++;
        } else {
            *empty = 0;
            if (c == '{')
                depth++;
            else if (c == '}')
                depth--;
            i++;
        }
    }
}

static void hbnf_run(hbnf_run_t *r, const char *text, int depth);

/* An `include`: read the file's statements in its place. */
static void hbnf_include(hbnf_run_t *r, const char *path, size_t line,
                         int depth) {
    char msg[512];
    const char *why, *outer = hbnf_file;
    char *text;

    if (depth >= 16) {
        snprintf(msg, sizeof msg, "%s: includes nested too deeply", path);
        hbnf_error(r, line, 0, msg, 0);
        return;
    }
    text = hbnf_read_file(path, &why);
    if (!text) {
        snprintf(msg, sizeof msg, "failed to include file %s", path);
        hbnf_error(r, line, 0, msg, 0);
        return;
    }
    hbnf_file = path;
    hbnf_run(r, text, depth + 1);
    hbnf_file = outer;
    free(text);
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

/* Every statement of one file's text. */
static void hbnf_run(hbnf_run_t *r, const char *text, int depth) {
    size_t i = 0, line = 1;

    for (;;) {
        size_t nl;
        int empty;
        size_t end = hbnf_stmt_end(text, i, &nl, &empty);
        if (!empty) {
            if (!depth)
                r->top_line = line;
            hbnf_stmt(r, text + i, end - i, line, depth);
        }
        line += nl;
        if (!text[end])
            break;
        i = end + 1;
        line++;
    }
}

/* Read a config: each statement is appended to *out, or with out NULL
   dropped once bound.  err, *err_line and *err_col hold the first error;
   false if there was any. */
static bool hbnf_stmts(const char *text, @ROOT_TYPE@ *out,
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
    hbnf_run(&r, text, 0);
    hbnf_macros_done();
    return r.errors == 0;
}
