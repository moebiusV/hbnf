%{
/* toy.y — the toy language as a yacc grammar, written as parse.y files are:
 * the actions build the config, one malloc'd node per rule on a list.  byacc
 * and bison both read it unchanged.  main() reads the file whole, times one
 * yyparse() and reports on the contract in timing.h. */
#include <stdlib.h>
#include <string.h>
#include "timing.h"

struct rule {
	struct rule *next;
	int action, dir;
	char *iface, *proto, *from_addr, *to_addr;
	long long from_port, to_port;
};
static struct rule *head, **tail = &head;
static long nrules;
static long long portsum;

int yylex(void);
void yyerror(const char *s) { fprintf(stderr, "yyerror: %s\n", s); }
%}
%union { long long number; char *string; }
%token PASS BLOCK MATCH IN OUT ON PROTO FROM TO PORT
%token <number> NUMBER
%token <string> WORD
%type <number> action dir
%%
config  : /* empty */ | config rule ;
rule    : action dir ON WORD PROTO WORD FROM WORD PORT NUMBER TO WORD PORT NUMBER
	{
		struct rule *r = calloc(1, sizeof *r);
		r->action = $1; r->dir = $2;
		r->iface = $4; r->proto = $6;
		r->from_addr = $8; r->from_port = $10;
		r->to_addr = $12; r->to_port = $14;
		*tail = r; tail = &r->next;
		nrules++;
		portsum += r->from_port + r->to_port;
	}
	;
action  : PASS { $$ = 0; } | BLOCK { $$ = 1; } | MATCH { $$ = 2; } ;
dir     : IN { $$ = 0; } | OUT { $$ = 1; } ;
%%
typedef struct yy_buffer_state *YY_BUFFER_STATE;
extern YY_BUFFER_STATE yy_scan_buffer(char *, size_t);

int main(int argc, char **argv) {
	size_t len;
	char *buf, *copy;
	double t0, ms;
	int rc;
	if (argc < 2) return 2;
	buf = bench_read(argv[1], &len);
	/* flex wants two trailing NULs for yy_scan_buffer. */
	copy = malloc(len + 2);
	memcpy(copy, buf, len);
	copy[len] = copy[len + 1] = '\0';
	free(buf);
	t0 = bench_now_ms();
	yy_scan_buffer(copy, len + 2);
	rc = yyparse();
	ms = bench_now_ms() - t0;
	return bench_report(rc == 0, len, nrules, portsum, ms);
}
