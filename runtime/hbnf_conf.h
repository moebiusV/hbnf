/* hbnf_conf.h -- what a daemon's config grammar needs besides its rules: the error callback
 * and the driver that reads a file a statement at a time, as parse.y's yyparse does.
 *
 * A grammar uses it from its own blocks.  The prologue includes it for the declarations, the
 * epilogue includes it again with HBNF_CONF_RUN defined for the driver, which is written in
 * terms of the parser the grammar made and so has to be in the same file:
 *
 *     { #include "ntpd.h"
 *       #include "hbnf_conf.h" }
 *     statements
 *     ...
 *     { #define HBNF_CONF_RUN
 *       #include "hbnf_conf.h"
 *       int parse_config(const char *filename, struct ntpd_conf *xconf) {
 *           conf = xconf;
 *           conf_init();
 *           return hbnf_conf_run(filename);
 *       } }
 *
 * hbnf_conf.c is linked in with the generated file.  */
#ifndef HBNF_CONF_H
#define HBNF_CONF_H

#include <stddef.h>

/* Called with each error's message and its 1-based line: a syntax error, or every error an
 * action reports.  The default prints "file:line: msg" to stderr and returns, as parse.y's
 * yyerror does; hbnf_conf_run then returns -1 and the daemon decides (exit at startup, keep the
 * running config on a reload).  Set conf_error to take the messages yourself. */
typedef void (*conf_error_fn)(size_t line, const char *msg);
extern conf_error_fn conf_error;
void conf_error_default(size_t line, const char *msg);

/* -D name=value: a macro the config cannot redefine; -1 without `=`.  The generated parser
 * defines it for a grammar with `macros`. */
int cmdline_symset(char *s);

/* The file being parsed (an included file while that one is read): the default handler's. */
extern const char *conf_file;

#endif /* HBNF_CONF_H */

#if defined(HBNF_CONF_RUN) && !defined(HBNF_CONF_RUN_DONE)
#define HBNF_CONF_RUN_DONE

/* Every error, syntax or action, as it is found: conf_file names the file it is in. */
static void hbnf_conf_report(size_t line, const char *msg) {
    const char *top = conf_file;

    if (hbnf_file)
        conf_file = hbnf_file;
    conf_error(line, msg);
    conf_file = top;
}

/* Read the file a block at a time and parse it one statement at a time: each statement is
 * parsed, bound by the grammar's actions and freed, strings and all, before the next is read,
 * so an action copies whatever it keeps.  Every error is reported as it is found and the parse
 * goes on, as parse.y's does.  0 when there were none, else -1. */
static int hbnf_conf_run(const char *filename) {
    FILE *f;
    hbnf_src_t src;
    char err[512];
    size_t line = 0, col = 0;
    bool ok;

    conf_file = filename;
    if (!(f = fopen(filename, "r"))) {
        conf_error(0, "cannot open file");
        return -1;
    }
    bind_report = hbnf_conf_report;
    hbnf_report = hbnf_conf_report;
    hbnf_src_file(&src, f);
    ok = hbnf_stmts(&src, NULL, err, sizeof err, &line, &col);
    hbnf_src_done(&src);
    hbnf_report = NULL;
    bind_report = NULL;
    fclose(f);
    return ok ? 0 : -1;
}

#endif /* HBNF_CONF_RUN */
