/* An ALGOL 60 pretty-printer, on the parser hbnf generates from algol60.hbnf.
 *
 *   hbnf corpus/algol60/algol60.hbnf --backend=c --writer --ast > a60.c
 *   cc -include a60.c -o pp corpus/algol60/pp.c        (or: sh tests/algol60-pp.sh)
 *   ./pp [--functional] [--clang] program.a60 > pretty.a60
 *
 * The parser reads the program into a tree (comments are nodes of it), and the
 * generated writer prints the tree back, token by token.  All this file does is
 * say what goes before each token (a newline and an indent, a blank, or nothing)
 * and, for --clang, what is written instead of it.  The grammar is not repeated.
 *
 *   (none)        the standard layout: one statement to a line, BEGIN/END on lines
 *                 of their own, comments kept.
 *   --functional  the program is rewritten first, in ways that keep its meaning, to
 *                 the functional style as far as ALGOL 60 goes (see fn_* below):
 *                 a conditional statement that assigns one variable either way is
 *                 an assignment of a conditional expression; BEGIN s END with no
 *                 declarations is s; one declaration per variable.
 *   --clang       braces for BEGIN and END, = for :=, == for =, && || ! and a
 *                 C look for the rest, comments as comments.  It looks like C and
 *                 is not C (for, arrays and procedure heads keep ALGOL's shape).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The alternatives of the rules the rewrites read (the %label names in algol60.hbnf). */
enum { ST_LABELLED = 1, ST_COND, ST_FOR, ST_PLAIN };
enum { UN_LABELLED = 1, UN_BLOCK, UN_ASSIGN, UN_GOTO, UN_CALL, UN_DUMMY };   /* the last is empty */
enum { EX_COND = 1, EX_PLAIN };
enum { DC_ARRAY = 1, DC_SWITCH, DC_PROC, DC_VARS };
enum { G_FOR = 1, G_UNCONDITIONAL };           /* statement_1: the group after IF ... THEN */

static int is(const char *a, const char *b) { return strcmp(a, b) == 0; }

static void check_alt(node_kind_t k, int alt, const char *name) {
    const char *got = node_alt_name(k, alt);
    if (!got || !is(got, name)) {
        fprintf(stderr, "pp: algol60.hbnf has changed: %s alternative %d is %s, not %s\n",
                node_kind_name(k), alt, got ? got : "(none)", name);
        exit(2);
    }
}
static void check_grammar(void) {
    check_alt(NODE_STATEMENT, ST_LABELLED, "labelled");
    check_alt(NODE_STATEMENT, ST_COND, "conditional");
    check_alt(NODE_STATEMENT, ST_FOR, "for");
    check_alt(NODE_STATEMENT, ST_PLAIN, "plain");
    check_alt(NODE_UNCONDITIONAL_STATEMENT, UN_BLOCK, "block");
    check_alt(NODE_UNCONDITIONAL_STATEMENT, UN_ASSIGN, "assign");
    check_alt(NODE_EXPRESSION, EX_COND, "conditional");
    check_alt(NODE_EXPRESSION, EX_PLAIN, "plain");
    check_alt(NODE_DECLARATION, DC_PROC, "procedure");
    check_alt(NODE_DECLARATION, DC_VARS, "variables");
}

/* ---- --functional: rewrites that keep the meaning ------------------------------ */

static void fn_stmt(statement_t *s);
static void fn_unc(unconditional_statement_t *u);
static void fn_block(block_t *b);

static int count_variables(const struct unconditional_statement_1_list *l, variable_t **only) {
    const struct unconditional_statement_1_s *n;
    int k = 0;
    for (n = l->head; n; n = n->_link) { k++; *only = (variable_t *)&n->variable; }
    return k;
}

/*  IF c THEN x := a ELSE x := b   is   x := IF c THEN a ELSE b
 *  (x a simple variable, so nothing but c and the one expression is evaluated either
 *  way; a is not itself a conditional expression, which would need brackets.)  The
 *  rewrite runs from the inside out, so a chain of ELSE IFs becomes one expression. */
static void fn_cond_assign(statement_t *s) {
    statement_1_t *g = s->statement_1;
    statement_t *e;
    unconditional_statement_t *u1, *u2, *copy;
    variable_t *v1 = NULL, *v2 = NULL;
    expression_t *x;

    if (g->_alt != G_UNCONDITIONAL || !g->statement_1_1.head || g->statement_1_1.head->_link)
        return;
    e = &g->statement_1_1.head->statement;
    if (e->_alt != ST_PLAIN) return;
    u1 = &g->unconditional_statement;
    u2 = e->unconditional_statement;
    if (u1->_alt != UN_ASSIGN || u2->_alt != UN_ASSIGN) return;
    if (count_variables(&u1->unconditional_statement_1, &v1) != 1
        || count_variables(&u2->unconditional_statement_1, &v2) != 1) return;
    if (v1->variable_1.head || v2->variable_1.head) return;       /* a[i]: left alone */
    if (!is(v1->identifier, v2->identifier)) return;
    if (u1->expression->_alt != EX_PLAIN) return;

    x = hbnf_alloc(sizeof *x);
    memset(x, 0, sizeof *x);
    x->_alt = EX_COND;
    x->if_clause = *s->if_clause;
    x->equivalence = u1->expression->equivalence;
    x->expression = u2->expression;
    copy = hbnf_alloc(sizeof *copy);
    *copy = *u1;
    copy->expression = x;
    s->_alt = ST_PLAIN;
    s->unconditional_statement = copy;
}

/*  BEGIN s END, with no declaration, comment or second statement, is s.  What is
 *  inside must be a plain statement that is neither labelled (a label belongs to
 *  its block) nor empty, so no ELSE can change hands and no scope is merged. */
static void fn_strip(unconditional_statement_t *u) {
    block_t *b = &u->block;
    unconditional_statement_t *inner;

    if (b->block_1.head || b->block_2.head || b->block_3.head) return;
    if (b->statement->_alt != ST_PLAIN) return;
    inner = b->statement->unconditional_statement;
    if (inner->_alt == UN_LABELLED || inner->_alt == UN_DUMMY) return;
    *u = *inner;
}

/*  REAL a, b;  is  REAL a;  REAL b;  (a comment after the ; stays after the last). */
static void fn_split(block_t *b) {
    block_2_t *d;
    for (d = b->block_2.head; d; d = d->_link) {
        struct identifiers_1_s *rest = d->declaration.identifiers.identifiers_1.head;
        block_2_t *first = d, *last = d;
        if (d->declaration._alt != DC_VARS || !rest) continue;
        d->declaration.identifiers.identifiers_1.head = NULL;
        d->declaration.identifiers.identifiers_1.tail = &d->declaration.identifiers.identifiers_1.head;
        for (; rest; rest = rest->_link) {
            block_2_t *n = hbnf_alloc(sizeof *n);
            *n = *d;
            n->declaration.identifiers.identifier = rest->identifier;
            n->_link = last->_link;
            last->_link = n;
            last = n;
        }
        for (d = first; d != last; d = d->_link) {        /* remarks go with the last one */
            d->block_2_1.head = NULL;
            d->block_2_1.tail = &d->block_2_1.head;
        }
    }
}

static void fn_block(block_t *b) {
    block_2_t *d;
    block_3_t *t;
    for (d = b->block_2.head; d; d = d->_link)
        if (d->declaration._alt == DC_PROC) fn_stmt(&d->declaration.statement);
    fn_stmt(b->statement);
    for (t = b->block_3.head; t; t = t->_link) fn_stmt(&t->statement);
    fn_split(b);
}

static void fn_unc(unconditional_statement_t *u) {
    switch (u->_alt) {
    case UN_LABELLED: fn_unc(u->unconditional_statement); break;
    case UN_BLOCK: fn_block(&u->block); fn_strip(u); break;
    default: break;
    }
}

static void fn_stmt(statement_t *s) {
    switch (s->_alt) {
    case ST_LABELLED: fn_stmt(s->statement); break;
    case ST_COND: {
        statement_1_t *g = s->statement_1;
        struct statement_1_1_s *el;
        if (g->_alt == G_FOR) fn_stmt(&g->for_statement.statement);
        else {
            fn_unc(&g->unconditional_statement);
            for (el = g->statement_1_1.head; el; el = el->_link) fn_stmt(&el->statement);
        }
        fn_cond_assign(s);
        break;
    }
    case ST_FOR: fn_stmt(&s->for_statement->statement); break;
    case ST_PLAIN: fn_unc(s->unconditional_statement); break;
    }
}

/* ---- the layout ----------------------------------------------------------------- */

typedef struct {
    int clang;
    int depth;               /* how many BEGINs are open */
    int brackets;            /* [ ] nesting: a : inside is a bound pair, not a label */
    int junk;                /* inside the text after END */
    const char *stack[48];   /* the rules entered and not yet left */
    int top;
    unsigned char cexpr[48]; /* that entry is the if-clause of a conditional expression */
    char prev[32], prev2[32];
    const char *repl;        /* what is written instead of the token (ev 3) */
    char out[160], rbuf[512], tbuf[512];
} pp_t;

static int in(const char *s, const char *const *set) {
    for (; *set; set++) if (is(s, *set)) return 1;
    return 0;
}

/* a token that ends an operand: a name, a number, a string, ) or ] */
static int operand_end(const char *s) {
    char c = s[0] ? s[strlen(s) - 1] : 0;
    if (c == '\'') return !in(s, (const char *const[]){ "'THEN'", "'ELSE'", "'DO'", "'BEGIN'", NULL });
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
        || c == ')' || c == ']' || c == '"';
}

static const char *newline(pp_t *p, const char *lead) {
    int n = p->depth < 0 ? 0 : p->depth;
    size_t k = strlen(lead);
    if (n > 30) n = 30;
    memcpy(p->out, lead, k);
    p->out[k] = '\n';
    memset(p->out + k + 1, ' ', 4 * (size_t)n);
    p->out[k + 1 + 4 * (size_t)n] = 0;
    return p->out;
}

/* --clang: what a token is written as */
static const char *c_word(pp_t *p, const char *s) {
    static const struct { const char *a, *c; } map[] = {
        { "'BEGIN'", "{" }, { "'END'", "}" }, { ":=", "=" }, { "=", "==" }, { "<>", "!=" },
        { "'AND'", "&&" }, { "'OR'", "||" }, { "'NOT'", "!" }, { "'EQUIV'", "==" },
        { "'TRUE'", "true" }, { "'FALSE'", "false" }, { "'POWER'", "**" }, { "^", "**" },
        { "'DIV'", "/" }, { "'LESS'", "<" }, { "'NOTGREATER'", "<=" }, { "'EQUAL'", "==" },
        { "'NOTLESS'", ">=" }, { "'GREATER'", ">" }, { "'NOTEQUAL'", "!=" },
        { "'IMPL'", "implies" },
    };
    size_t i, k;
    for (i = 0; i < sizeof map / sizeof *map; i++) if (is(s, map[i].a)) return map[i].c;
    if (s[0] == '\'' && s[1] && s[strlen(s) - 1] == '\'') {      /* 'INTEGER' is integer */
        k = strlen(s) - 2;
        if (k >= sizeof p->rbuf) k = sizeof p->rbuf - 1;
        for (i = 0; i < k; i++) p->rbuf[i] = (char)(s[1 + i] | 0x20);
        p->rbuf[k] = 0;
        return p->rbuf;
    }
    return NULL;
}

/* 'COMMENT' text ;  as  slash-star text star-slash  (the text without the blanks round it) */
static const char *c_comment(pp_t *p, const char *s) {
    size_t b = 9, e = strlen(s);
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\n' || s[b] == '\r')) b++;
    if (e > b && s[e - 1] == ';') e--;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\n' || s[e - 1] == '\r')) e--;
    if (e - b > sizeof p->rbuf - 8) e = b + sizeof p->rbuf - 8;
    snprintf(p->rbuf, sizeof p->rbuf, "/* %.*s */", (int)(e - b), s + b);
    return p->rbuf;
}

/* the text without the white space at its ends: the text after END has the line's end in it */
static const char *trimmed(pp_t *p, const char *s) {
    size_t b = 0, e = strlen(s);
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\n' || s[b] == '\r')) b++;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\n' || s[e - 1] == '\r')) e--;
    if (e - b >= sizeof p->tbuf) e = b + sizeof p->tbuf - 1;
    memcpy(p->tbuf, s + b, e - b);
    p->tbuf[e - b] = 0;
    return p->tbuf;
}

static const char *layout(void *ctx, int ev, const char *s) {
    static const char *const opening[] = { "(", "[", NULL };
    static const char *const closing[] = { ")", "]", ";", ",", NULL };
    static const char *const body[] = { "'THEN'", "'ELSE'", "'DO'", NULL };
    static const char *const ends[] = { ";", "'BEGIN'", "'END'", NULL };
    static const char *const ends_else[] = { ";", "'END'", NULL };
    pp_t *p = ctx;
    const char *sep, *top;
    int remark, in_expr, cexpr_if;

    if (ev == 1) {
        int ce = is(s, "if-clause") && p->top && is(p->stack[p->top - 1], "expression");
        if (p->top < 48) { p->stack[p->top] = s; p->cexpr[p->top++] = (unsigned char)ce; }
        if (is(s, "end-junk")) p->junk = 1;
        return NULL;
    }
    if (ev == 2) {
        if (p->top) p->top--;
        if (is(s, "end-junk")) p->junk = 0;
        return NULL;
    }
    if (ev == 3) return p->repl;

    p->repl = NULL;
    top = p->top ? p->stack[p->top - 1] : "";
    remark = strncmp(s, "'COMMENT'", 9) == 0;     /* a comment is one token, ending in ; */
    in_expr = is(top, "expression");               /* an ELSE here belongs to an expression */
    cexpr_if = p->top && p->cexpr[p->top - 1];     /* in the IF ... THEN of a conditional expression */

    if (p->junk) {                       /* the text after END, as it came */
        sep = is(p->prev, "'END'") ? " " : "";
        if (!p->clang) p->repl = trimmed(p, s);
    } else if (!p->prev[0]) {
        sep = "";
    } else if (remark) {                 /* a comment stands on a line of its own */
        sep = newline(p, "");
    } else if (is(s, "'END'")) {
        p->depth--;
        sep = newline(p, p->clang && !in(p->prev, ends) ? ";" : "");
    } else if (is(p->prev, "'BEGIN'") || is(p->prev, ";")) {
        sep = newline(p, "");
    } else if (is(s, "'ELSE'") && !in_expr) {
        sep = newline(p, p->clang && !in(p->prev, ends_else) ? ";" : "");
    } else if (is(s, "'BEGIN'") && in(p->prev, body)) {
        sep = " ";
    } else if (in(s, closing) || in(p->prev, opening)
               || (p->clang && is(s, "'THEN'") && !cexpr_if)
               || (p->clang && is(s, "'DO'"))) {
        sep = "";
    } else if (p->clang && (is(p->prev, "'IF'") || is(p->prev, "'FOR'")) && !cexpr_if) {
        sep = "";                        /* if (cond) */
    } else if (is(s, "(") || is(s, "[")) {
        sep = operand_end(p->prev) && p->prev[0] != '\'' ? "" : " ";
    } else if (is(s, ":")) {
        sep = "";
    } else if ((is(p->prev, "+") || is(p->prev, "-")) && !operand_end(p->prev2)) {
        sep = "";                        /* a sign, not an operator */
    } else if (is(p->prev, ":")) {
        sep = p->brackets ? "" : " ";
    } else {
        sep = " ";
    }

    if (p->clang) {                      /* what is written instead */
        if (p->junk) {               /* the text after END is a comment: a run of it is one */
            if (is(s, "'")) { p->repl = ""; sep = ""; }
            else { snprintf(p->rbuf, sizeof p->rbuf, "/* %s */", trimmed(p, s)); p->repl = p->rbuf; }
        } else if (remark) p->repl = c_comment(p, s);
        else if (is(s, ";") && is(p->prev, "'END'")) { p->repl = ""; sep = ""; }   /* } needs none */
        else if (is(s, "'IF'")) p->repl = cexpr_if ? "" : "if (";                  /* c ? a : b */
        else if (is(s, "'THEN'")) p->repl = cexpr_if ? "?" : ")";
        else if (is(s, "'ELSE'") && in_expr) p->repl = ":";
        else if (is(s, "'FOR'")) p->repl = "for (";
        else if (is(s, "'DO'")) p->repl = ")";
        else p->repl = c_word(p, s);
    }

    if (is(s, "'BEGIN'")) p->depth++;
    if (is(s, "[")) p->brackets++;
    if (is(s, "]") && p->brackets) p->brackets--;
    if (p->junk) return sep;             /* the text after END does not move what came before */
    strncpy(p->prev2, p->prev, sizeof p->prev2 - 1);
    strncpy(p->prev, remark || (p->clang && is(s, ";") && is(p->prev, "'END'")) ? ";" : s,
            sizeof p->prev - 1);
    p->prev[sizeof p->prev - 1] = 0;
    return sep;
}

static char *slurp(FILE *f) {
    size_t n = 0, cap = 1 << 16;
    char *b = malloc(cap);
    size_t got;
    if (!b) exit(2);
    while ((got = fread(b + n, 1, cap - n - 1, f)) > 0) {
        n += got;
        if (n + 1 >= cap) { cap *= 2; b = realloc(b, cap); if (!b) exit(2); }
    }
    b[n] = 0;
    return b;
}

/* Parse text and write it as the printer lays it out; NULL when it does not parse. */
static char *pretty(const char *text, int functional, int clang, char *err, size_t errlen) {
    program_t tree;
    size_t line, col, n;
    char *out;
    pp_t st;

    if (!parse_text(text, &tree, err, errlen, &line, &col)) return NULL;
    if (functional) fn_block(&tree.block);
    hbnf_write_layout = layout;
    hbnf_write_layout_ctx = &st;
    memset(&st, 0, sizeof st);                 /* the first pass measures, the second writes */
    st.clang = clang;
    n = write_program(&tree, NULL, 0);
    if (n == (size_t)-1) { snprintf(err, errlen, "%s", hbnf_write_error); return NULL; }
    out = malloc(n + 2);
    if (!out) exit(2);
    memset(&st, 0, sizeof st);
    st.clang = clang;
    write_program(&tree, out, n + 1);
    out[n] = '\n';
    out[n + 1] = 0;
    return out;
}

int main(int argc, char **argv) {
    char err[512], *text, *a, *b;
    FILE *f = stdin;
    int check = 0, functional = 0, clang = 0, i;
    const char *path = NULL;

    for (i = 1; i < argc; i++) {
        if (is(argv[i], "-c")) check = 1;           /* print it twice over, as a test */
        else if (is(argv[i], "--functional")) functional = 1;
        else if (is(argv[i], "--clang")) clang = 1;
        else path = argv[i];
    }
    check_grammar();
    if (path) {
        f = fopen(path, "rb");
        if (!f) { perror(path); return 2; }
    }
    text = slurp(f);
    a = pretty(text, functional, clang, err, sizeof err);
    if (!a) { fprintf(stderr, "pp: %s\n", err); return 1; }
    if (check && !clang) {            /* what it printed must read, and print the same */
        b = pretty(a, functional, clang, err, sizeof err);
        if (!b) { fprintf(stderr, "pp: the output does not parse: %s\n%s", err, a); return 1; }
        if (strcmp(a, b)) { fprintf(stderr, "pp: not idempotent\n--- first\n%s--- second\n%s", a, b); return 1; }
        return 0;
    }
    fputs(a, stdout);
    return 0;
}
