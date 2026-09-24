/* The daemon's own conf tree, filled by parse_config(); the action jets
   build it into the caller's struct.  The `conf` global is the daemon's
   (declared in its header, included by the grammar's preamble). */
int parse_config(const char *filename, @CONF_TYPE@ *conf);

/* yyerror-style error handler: called by the parser at the point of failure
   with the caret message and its 1-based line.  The default handler prints
   "file:line: msg" (file taken from conf_file) and exit(1)s; override
   conf_error to take the message yourself, in which case parse_config returns
   -1 after the handler. */
typedef void (*conf_error_fn)(size_t line, const char *msg);
extern conf_error_fn conf_error;

/* Filename being parsed: set by parse_config, used by the default handler. */
extern const char *conf_file;
