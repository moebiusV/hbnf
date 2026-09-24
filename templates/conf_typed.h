/* The daemon's own conf tree, filled by parse_config(); the action jets
   build it into the caller's struct.  The `conf` global is the daemon's
   (declared in its header, included by the grammar's preamble). */
int parse_config(const char *filename, @CONF_TYPE@ *conf);

/* yyerror-style error handler: called with each error's message and its
   1-based line (a syntax error, or every error an action jet reports).  The
   default handler prints "file:line: msg" (file taken from conf_file) to
   stderr and returns, as parse.y's yyerror does; parse_config then returns
   -1 and the daemon decides (exit at startup, keep the running config on a
   reload).  Override conf_error to take the messages yourself. */
typedef void (*conf_error_fn)(size_t line, const char *msg);
extern conf_error_fn conf_error;

/* Filename being parsed: set by parse_config, used by the default handler. */
extern const char *conf_file;
