/* The configuration tree root, populated by parse_config(). */
extern @ROOT_TYPE@ *conf;

/* Error handler: default prints "file:line: msg" and exits; override to
   handle errors yourself (parse_config then returns -1 instead). */
typedef void (*conf_error_fn)(const char *file, size_t line, const char *msg);
extern conf_error_fn conf_error;

/* Read filename, populate the global `conf`.  Returns 0 on success, -1 on
   error (after calling conf_error). */
int parse_config(const char *filename);
