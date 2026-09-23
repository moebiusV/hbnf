/* Dump the authoritative field-by-field layout of OpenBSD's `struct pf_rule`
 * (and its nested structs) — the byte-identity contract the generated parser
 * must meet.  Compiled by bytetest.sh against the real headers.  */
#include <stdio.h>
#include <stddef.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/pfvar.h>

#define O(t, f) printf("%-32s offsetof=%-4zu sizeof=%zu\n", \
	#t "." #f, offsetof(struct t, f), sizeof(((struct t *)0)->f))
#define S(t)    printf("SIZEOF %-28s = %zu\n", #t, sizeof(t))

int main(void)
{
	S(struct pf_rule);
	S(struct pf_rule_addr);
	S(struct pf_pool);
	S(struct pf_ruleset);
	S(struct pf_addr_wrap);
	S(struct pf_addr);
	S(struct pf_rule_uid);
	S(struct pf_rule_gid);
	S(struct pf_threshold);

	puts("--- struct pf_rule fields ---");
	O(pf_rule, src);
	O(pf_rule, dst);
	O(pf_rule, skip);
	O(pf_rule, label);
	O(pf_rule, ifname);
	O(pf_rule, rcv_ifname);
	O(pf_rule, qname);
	O(pf_rule, pqname);
	O(pf_rule, tagname);
	O(pf_rule, match_tagname);
	O(pf_rule, overload_tblname);
	O(pf_rule, entries);
	O(pf_rule, nat);
	O(pf_rule, rdr);
	O(pf_rule, route);
	O(pf_rule, pktrate);
	O(pf_rule, evaluations);
	O(pf_rule, packets);
	O(pf_rule, bytes);
	O(pf_rule, kif);
	O(pf_rule, rcv_kif);
	O(pf_rule, anchor);
	O(pf_rule, overload_tbl);
	O(pf_rule, os_fingerprint);
	O(pf_rule, rtableid);
	O(pf_rule, onrdomain);
	O(pf_rule, timeout);
	O(pf_rule, states_cur);
	O(pf_rule, states_tot);
	O(pf_rule, max_states);
	O(pf_rule, src_nodes);
	O(pf_rule, max_src_nodes);
	O(pf_rule, max_src_states);
	O(pf_rule, max_src_conn);
	O(pf_rule, max_src_conn_rate);
	O(pf_rule, qid);
	O(pf_rule, pqid);
	O(pf_rule, rt_listid);
	O(pf_rule, nr);
	O(pf_rule, prob);
	O(pf_rule, cuid);
	O(pf_rule, cpid);
	O(pf_rule, return_icmp);
	O(pf_rule, return_icmp6);
	O(pf_rule, max_mss);
	O(pf_rule, tag);
	O(pf_rule, match_tag);
	O(pf_rule, scrub_flags);
	O(pf_rule, delay);
	O(pf_rule, uid);
	O(pf_rule, gid);
	O(pf_rule, rule_flag);
	O(pf_rule, action);
	O(pf_rule, direction);
	O(pf_rule, log);
	O(pf_rule, logif);
	O(pf_rule, quick);
	O(pf_rule, ifnot);
	O(pf_rule, match_tag_not);
	O(pf_rule, keep_state);
	O(pf_rule, af);
	O(pf_rule, proto);
	O(pf_rule, type);
	O(pf_rule, code);
	O(pf_rule, flags);
	O(pf_rule, flagset);
	O(pf_rule, min_ttl);
	O(pf_rule, allow_opts);
	O(pf_rule, rt);
	O(pf_rule, return_ttl);
	O(pf_rule, tos);
	O(pf_rule, set_tos);
	O(pf_rule, anchor_relative);
	O(pf_rule, anchor_wildcard);
	O(pf_rule, flush);
	O(pf_rule, prio);
	O(pf_rule, set_prio);
	O(pf_rule, naf);
	O(pf_rule, rcvifnot);
	O(pf_rule, statelim);
	O(pf_rule, sourcelim);
	O(pf_rule, divert);
	O(pf_rule, exptime);
	return 0;
}
