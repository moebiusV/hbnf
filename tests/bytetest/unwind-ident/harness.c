/* unwind-ident.sh's main: parse_config(argv[1]) and a canonical dump of the
   struct uw_conf it returns.  Built twice, once with parse.y's parser and
   once with hbnf's, against the same unwind headers.  Also the pieces of
   unwind.c and resolver.c the parse needs, and OpenBSD's strtonum. */
#include <sys/types.h>
#include <sys/queue.h>
#include <sys/tree.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <syslog.h>

#include "log.h"
#include "unwind.h"

uint32_t cmd_opts;

/* unwind.c's */
struct uw_conf *
config_new_empty(void)
{
	struct uw_conf *xconf;

	xconf = calloc(1, sizeof(*xconf));
	if (xconf == NULL)
		fatal(NULL);
	TAILQ_INIT(&xconf->uw_forwarder_list);
	TAILQ_INIT(&xconf->uw_dot_forwarder_list);
	RB_INIT(&xconf->force);
	return (xconf);
}

/* resolver.c's */
int
force_tree_cmp(struct force_tree_entry *a, struct force_tree_entry *b)
{
	return strcasecmp(a->domain, b->domain);
}

RB_GENERATE(force_tree, force_tree_entry, entry, force_tree_cmp)

/* OpenBSD's strtonum: parse.y's lexer reads NUMBER tokens with it. */
long long
strtonum(const char *numstr, long long minval, long long maxval,
    const char **errstrp)
{
	char *ep;
	long long val;

	if (errstrp)
		*errstrp = NULL;
	if (numstr == NULL || *numstr == '\0') {
		if (errstrp)
			*errstrp = "invalid";
		return 0;
	}
	errno = 0;
	val = strtoll(numstr, &ep, 10);
	if (ep == numstr || *ep != '\0' || errno == ERANGE) {
		if (errstrp)
			*errstrp = "invalid";
		return 0;
	}
	if (val < minval || val > maxval) {
		if (errstrp)
			*errstrp = val < minval ? "too small" : "too large";
		return 0;
	}
	return val;
}

/* Every field of the tree: scalars and arrays by value, strings by
   content, lists and the force tree in order. */
static void
dump_uw_conf(const struct uw_conf *c)
{
	const struct uw_forwarder *f;
	struct force_tree_entry *e;
	int i;

	printf("res_pref.len %d:", c->res_pref.len);
	for (i = 0; i < c->res_pref.len; i++)
		printf(" %s", uw_resolver_type_str[c->res_pref.types[i]]);
	printf("\nenabled_resolvers:");
	for (i = 0; i < UW_RES_NONE; i++)
		printf(" %d", c->enabled_resolvers[i]);
	printf("\nforce_resolvers:");
	for (i = 0; i < UW_RES_NONE; i++)
		printf(" %d", c->force_resolvers[i]);
	printf("\nblocklist_file %s%s%s, blocklist_log %d\n",
	    c->blocklist_file ? "\"" : "",
	    c->blocklist_file ? c->blocklist_file : "NULL",
	    c->blocklist_file ? "\"" : "", c->blocklist_log);
	TAILQ_FOREACH(f, &c->uw_forwarder_list, entry)
		printf("forwarder ip \"%s\" auth_name \"%s\" port %u if_index %u src %d\n",
		    f->ip, f->auth_name, f->port, f->if_index, f->src);
	TAILQ_FOREACH(f, &c->uw_dot_forwarder_list, entry)
		printf("dot_forwarder ip \"%s\" auth_name \"%s\" port %u if_index %u src %d\n",
		    f->ip, f->auth_name, f->port, f->if_index, f->src);
	RB_FOREACH(e, force_tree, (struct force_tree *)&c->force)
		printf("force \"%s\" type %s acceptbogus %d\n", e->domain,
		    uw_resolver_type_str[e->type], e->acceptbogus);
}

int
main(int argc, char **argv)
{
	struct uw_conf *c;

	if (argc != 2) {
		fprintf(stderr, "usage: %s config\n", argv[0]);
		return 2;
	}
	log_init(1, LOG_DAEMON);
	if ((c = parse_config(argv[1])) == NULL) {
		fprintf(stderr, "parse_config failed\n");
		return 1;
	}
	dump_uw_conf(c);
	return 0;
}
