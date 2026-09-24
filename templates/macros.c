/* ------------------------------------------------------------------ */
/* Macros (the grammar's `macros` directive), as parse.y has them.  A   */
/* statement the macros rule matches whole defines one: its first token */
/* is the name, and the tokens after `=`, joined by spaces, the value.  */
/* `$name` at the start of a word, outside quotes and comments, expands */
/* to the value, glued to what follows (`$net.5`) and not expanded      */
/* again.  cmdline_symset("name=value") (-D) defines one the config     */
/* cannot redefine; the others are dropped when the parse ends.         */
/* ------------------------------------------------------------------ */

typedef struct hbnf_sym {
    struct hbnf_sym *next;
    char *nam, *val;
    char *file;         /* where it was defined: NULL for the top file */
    size_t line;        /* 0: the command line */
    int persist;
} hbnf_sym;

static hbnf_sym *hbnf_syms;

/* Where each expansion in the current statement landed (its line within
   the statement, its columns), for the trail on an error inside one. */
typedef struct {
    size_t line, col0, col1;
    const hbnf_sym *sym;
} hbnf_seg;

static hbnf_seg hbnf_segs[16];
static size_t hbnf_nsegs;

static void hbnf_sym_free(hbnf_sym *y) {
    free(y->nam);
    free(y->val);
    free(y->file);
    free(y);
}

static hbnf_sym *hbnf_symget(const char *nam, size_t len) {
    hbnf_sym *y;

    for (y = hbnf_syms; y; y = y->next)
        if (strlen(y->nam) == len && memcmp(y->nam, nam, len) == 0)
            return y;
    return NULL;
}

/* parse.y's symset: a command-line macro is not redefined. */
static int hbnf_symset(const char *nam, size_t len, const char *val,
                       int persist, size_t line) {
    hbnf_sym *y = hbnf_symget(nam, len), **pp;

    if (y) {
        if (y->persist)
            return 0;
        for (pp = &hbnf_syms; *pp != y; pp = &(*pp)->next)
            ;
        *pp = y->next;
        hbnf_sym_free(y);
    }
    y = (hbnf_sym *)calloc(1, sizeof *y);
    if (!y)
        hbnf_oom();
    y->nam = hbnf_strndup(nam, len);
    y->val = hbnf_strndup(val, strlen(val));
    y->file = hbnf_file ? hbnf_strndup(hbnf_file, strlen(hbnf_file)) : NULL;
    y->line = line;
    y->persist = persist;
    y->next = hbnf_syms;
    hbnf_syms = y;
    return 0;
}

/* -D name=value: the name ends at the last `=`, as in parse.y. */
int cmdline_symset(char *s) {
    const char *val = strrchr(s, '=');

    if (!val)
        return -1;
    return hbnf_symset(s, (size_t)(val - s), val + 1, 1, 0);
}

/* A statement the macros rule matched: remember name = value. */
static void hbnf_define(const token_t *toks, size_t n, size_t line) {
    size_t i, eq, len = 0;
    char *val, *p;

    if (!hbnf_is_macro(toks, n))
        return;
    for (eq = 1; eq < n; eq++)
        if (toks[eq].kind == TOK_PUNCT && toks[eq].len == 1
            && toks[eq].text[0] == '=')
            break;
    for (i = eq + 1; i < n && toks[i].kind != TOK_EOF; i++)
        len += toks[i].len + 1;
    val = p = (char *)malloc(len + 1);
    if (!val)
        hbnf_oom();
    for (i = eq + 1; i < n && toks[i].kind != TOK_EOF; i++) {
        size_t k;
        if (p != val)
            *p++ = ' ';
        for (k = 0; k < toks[i].len; k++)   /* a value is one line */
            *p++ = toks[i].text[k] == '\n' ? ' ' : toks[i].text[k];
    }
    *p = '\0';
    hbnf_symset(toks[0].text, toks[0].len, val, 0, line);
    free(val);
}

/* Append s[0..n) to the growing buffer *o. */
static void hbnf_put(char **o, size_t *used, size_t *cap, const char *s,
                     size_t n) {
    if (*used + n + 1 > *cap) {
        size_t nc = (*used + n + 1) * 2;
        char *no = (char *)realloc(*o, nc);
        if (!no)
            hbnf_oom();
        *o = no;
        *cap = nc;
    }
    memcpy(*o + *used, s, n);
    *used += n;
}

/* The statement s[0..len) with its macros expanded, NUL-terminated;
   NULL, with msg, if one is not defined. */
static char *hbnf_expand(const char *s, size_t len, char *msg, size_t msglen) {
    size_t cap = len + 1, used = 0, i = 0, line = 0, col = 1;
    char *o = (char *)malloc(cap);

    if (!o)
        hbnf_oom();
    hbnf_nsegs = 0;
    if (!memchr(s, '$', len)) {                 /* most statements */
        memcpy(o, s, len);
        o[len] = '\0';
        return o;
    }
    while (i < len) {
        char c = s[i];
        size_t j = i + 1;
        if (c != '"' && c != '#' && c != '$' && c != '\n') {
            while (j < len && s[j] != '"' && s[j] != '#' && s[j] != '$'
                   && s[j] != '\n')
                j++;
            hbnf_put(&o, &used, &cap, s + i, j - i);
            col += j - i;
            i = j;
            continue;
        }
        if (c == '"') {                         /* a quoted string, as is */
            while (j < len && s[j] != '"')
                j += (s[j] == '\\' && j + 1 < len) ? 2 : 1;
            if (j < len)
                j++;
        } else if (c == '#') {                  /* a comment, as is */
            while (j < len && s[j] != '\n')
                j++;
        } else if (c == '$' && (used == 0 || !lex_word_char(o[used - 1]))) {
            const hbnf_sym *y;
            size_t vl;
            while (j < len && (isalnum((unsigned char)s[j]) || s[j] == '_'))
                j++;
            y = hbnf_symget(s + i + 1, j - i - 1);
            if (!y) {
                snprintf(msg, msglen, "macro '%.*s' not defined",
                         (int)(j - i - 1), s + i + 1);
                free(o);
                return NULL;
            }
            vl = strlen(y->val);
            if (hbnf_nsegs < sizeof hbnf_segs / sizeof hbnf_segs[0]) {
                hbnf_segs[hbnf_nsegs].line = line;
                hbnf_segs[hbnf_nsegs].col0 = col;
                hbnf_segs[hbnf_nsegs].col1 = col + vl;
                hbnf_segs[hbnf_nsegs].sym = y;
                hbnf_nsegs++;
            }
            hbnf_put(&o, &used, &cap, y->val, vl);
            col += vl;
            i = j;
            continue;
        }
        hbnf_put(&o, &used, &cap, s + i, j - i);
        for (; i < j; i++) {
            if (s[i] == '\n') {
                line++;
                col = 1;
            } else {
                col++;
            }
        }
    }
    o[used] = '\0';
    return o;
}

/* On an error in or after an expanded value on the error's line, say
   where the value came from: the one the error is in, else the last one
   before it. */
static void hbnf_trail(char *msg, size_t msglen, size_t line, size_t col) {
    size_t k, used = strlen(msg);
    const hbnf_seg *g = NULL;

    for (k = 0; k < hbnf_nsegs; k++) {
        if (hbnf_segs[k].line != line || col < hbnf_segs[k].col0)
            continue;
        g = &hbnf_segs[k];
        if (col < g->col1)
            break;
    }
    if (g) {
        if (!g->sym->line)
            snprintf(msg + used, msglen - used,
                     "\n  ($%s = \"%s\", from the command line)",
                     g->sym->nam, g->sym->val);
        else if (g->sym->file)
            snprintf(msg + used, msglen - used,
                     "\n  ($%s = \"%s\", defined at %s:%zu)",
                     g->sym->nam, g->sym->val, g->sym->file, g->sym->line);
        else
            snprintf(msg + used, msglen - used,
                     "\n  ($%s = \"%s\", defined at line %zu)",
                     g->sym->nam, g->sym->val, g->sym->line);
    }
}

/* The end of a parse: the config's own macros go, -D ones stay. */
static void hbnf_macros_done(void) {
    hbnf_sym **pp = &hbnf_syms, *y;

    while ((y = *pp) != NULL) {
        if (y->persist) {
            pp = &y->next;
        } else {
            *pp = y->next;
            hbnf_sym_free(y);
        }
    }
}
