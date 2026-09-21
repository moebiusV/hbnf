/* The configuration tree root, populated by parse_config(). */
extern @ROOT_TYPE@ *conf;

/* yyerror-style error handler: called by the parser at the point of failure
   with the caret message and its 1-based line.  The default handler prints
   "file:line: msg" (file taken from conf_file) and exit(1)s; override
   conf_error to take the message yourself, in which case parse_config returns
   -1 after the handler. */
typedef void (*conf_error_fn)(size_t line, const char *msg);
extern conf_error_fn conf_error;

/* Filename being parsed: set by parse_config, used by the default handler. */
extern const char *conf_file;

/* Read filename, populate the global `conf`.  Returns 0 on success, -1 on
   error (after conf_error has been called). */
int parse_config(const char *filename);

/* Return the current config root (NULL before a successful parse_config).
   Convenience for FFI languages that cannot read the `conf` global. */
@ROOT_TYPE@ *conf_ptr(void);
