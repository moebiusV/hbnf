/* unused.c -- parse.y entry points the benchmark input never reaches (tables, queues, anchors,
 * `set` options, fingerprints).  Each aborts if it is called, so a benchmark file that strays
 * into one fails loudly instead of timing a no-op.  No headers: the types do not matter here. */
#include <stdlib.h>
#include <stdio.h>
int add_opt_table() { fputs("unused: add_opt_table\n", stderr); abort(); }
int append_addr_host() { fputs("unused: append_addr_host\n", stderr); abort(); }
int gen_dynnode() { fputs("unused: gen_dynnode\n", stderr); abort(); }
int geticmpcodebyname() { fputs("unused: geticmpcodebyname\n", stderr); abort(); }
int geticmptypebyname() { fputs("unused: geticmptypebyname\n", stderr); abort(); }
int pf_anchor_setup() { fputs("unused: pf_anchor_setup\n", stderr); abort(); }
int pf_find_or_create_ruleset() { fputs("unused: pf_find_or_create_ruleset\n", stderr); abort(); }
int pf_init_ruleset() { fputs("unused: pf_init_ruleset\n", stderr); abort(); }
int pf_opt_create_table() { fputs("unused: pf_opt_create_table\n", stderr); abort(); }
int pf_remove_if_empty_ruleset() { fputs("unused: pf_remove_if_empty_ruleset\n", stderr); abort(); }
int pf_strerror() { fputs("unused: pf_strerror\n", stderr); abort(); }
int pfctl_add_queue() { fputs("unused: pfctl_add_queue\n", stderr); abort(); }
int pfctl_add_sourcelim() { fputs("unused: pfctl_add_sourcelim\n", stderr); abort(); }
int pfctl_add_statelim() { fputs("unused: pfctl_add_statelim\n", stderr); abort(); }
int pfctl_define_table() { fputs("unused: pfctl_define_table\n", stderr); abort(); }
int pfctl_file_fingerprints() { fputs("unused: pfctl_file_fingerprints\n", stderr); abort(); }
int pfctl_find_queue() { fputs("unused: pfctl_find_queue\n", stderr); abort(); }
int pfctl_get_fingerprint() { fputs("unused: pfctl_get_fingerprint\n", stderr); abort(); }
int pfctl_get_sourcelim_nm() { fputs("unused: pfctl_get_sourcelim_nm\n", stderr); abort(); }
int pfctl_get_statelim_nm() { fputs("unused: pfctl_get_statelim_nm\n", stderr); abort(); }
int pfctl_rules() { fputs("unused: pfctl_rules\n", stderr); abort(); }
int pfctl_set_debug() { fputs("unused: pfctl_set_debug\n", stderr); abort(); }
int pfctl_set_hostid() { fputs("unused: pfctl_set_hostid\n", stderr); abort(); }
int pfctl_set_interface_flags() { fputs("unused: pfctl_set_interface_flags\n", stderr); abort(); }
int pfctl_set_limit() { fputs("unused: pfctl_set_limit\n", stderr); abort(); }
int pfctl_set_logif() { fputs("unused: pfctl_set_logif\n", stderr); abort(); }
int pfctl_set_optimization() { fputs("unused: pfctl_set_optimization\n", stderr); abort(); }
int pfctl_set_reassembly() { fputs("unused: pfctl_set_reassembly\n", stderr); abort(); }
int pfctl_set_syncookies() { fputs("unused: pfctl_set_syncookies\n", stderr); abort(); }
int pfctl_set_timeout() { fputs("unused: pfctl_set_timeout\n", stderr); abort(); }
int pfr_buf_clear() { fputs("unused: pfr_buf_clear\n", stderr); abort(); }
int pfr_buf_load() { fputs("unused: pfr_buf_load\n", stderr); abort(); }
int pfr_ktablehead_RB_INSERT() { fputs("unused: pfr_ktablehead_RB_INSERT\n", stderr); abort(); }
int pfr_ktablehead_RB_MINMAX() { fputs("unused: pfr_ktablehead_RB_MINMAX\n", stderr); abort(); }
int pfr_ktablehead_RB_NEXT() { fputs("unused: pfr_ktablehead_RB_NEXT\n", stderr); abort(); }
int pfr_ktablehead_RB_REMOVE() { fputs("unused: pfr_ktablehead_RB_REMOVE\n", stderr); abort(); }
int print_tabledef() { fputs("unused: print_tabledef\n", stderr); abort(); }
int warn_duplicate_tables() { fputs("unused: warn_duplicate_tables\n", stderr); abort(); }
/* these three do nothing for a plain address */
void set_ipmask() {}
int check_netmask() { return 0; }
int unmask() { return 0; }
char pfr_ktables[64];
struct { void *first, **last; } qspecs = { 0, &qspecs.first }, rootqs = { 0, &rootqs.first };
struct { const char *name; int timeout; } pf_timeouts[] = { { 0, 0 } };
