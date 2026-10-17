/* ts_toy.c — time tree-sitter parsing the toy file with the generated
 * parser.c and libtree-sitter's own lib.c.  Only ts_parser_parse_string is
 * timed; the walk that reads the ports back (to check the parse) is not. */
#include <string.h>
#include <tree_sitter/api.h>
#include "timing.h"

const TSLanguage *tree_sitter_toy(void);

int main(int argc, char **argv) {
	size_t len;
	char *buf;
	TSParser *p;
	TSTree *t;
	TSNode root;
	uint32_t i, n;
	long count = 0;
	long long sum = 0;
	double t0, ms;
	int ok;

	if (argc < 2) return 2;
	buf = bench_read(argv[1], &len);
	p = ts_parser_new();
	ts_parser_set_language(p, tree_sitter_toy());
	t0 = bench_now_ms();
	t = ts_parser_parse_string(p, NULL, buf, (uint32_t)len);
	ms = bench_now_ms() - t0;
	if (argc > 2 && strcmp(argv[2], "edit") == 0) {
		/* A one-byte edit: a blank at the start of a line, half way down the
		 * file.  Only the re-parse with the old tree is timed. */
		size_t at = len / 2, k;
		uint32_t row = 0;
		char *nb;
		TSInputEdit ed;
		TSTree *t2;
		while (at < len && buf[at - 1] != '\n') at++;
		for (k = 0; k < at; k++)
			if (buf[k] == '\n') row++;
		nb = (char *)malloc(len + 2);
		memcpy(nb, buf, at);
		nb[at] = ' ';
		memcpy(nb + at + 1, buf + at, len - at + 1);
		ed.start_byte = ed.old_end_byte = (uint32_t)at;
		ed.new_end_byte = (uint32_t)at + 1;
		ed.start_point.row = ed.old_end_point.row = ed.new_end_point.row = row;
		ed.start_point.column = ed.old_end_point.column = 0;
		ed.new_end_point.column = 1;
		ts_tree_edit(t, &ed);
		t0 = bench_now_ms();
		t2 = ts_parser_parse_string(p, t, nb, (uint32_t)len + 1);
		ms = bench_now_ms() - t0;
		t = t2;
		buf = nb;
		len++;
	}
	root = ts_tree_root_node(t);
	ok = !ts_node_has_error(root);
	n = ts_node_named_child_count(root);
	for (i = 0; ok && i < n; i++) {
		TSNode r = ts_node_named_child(root, i);
		TSNode a = ts_node_child_by_field_name(r, "from_port", 9);
		TSNode b = ts_node_child_by_field_name(r, "to_port", 7);
		count++;
		sum += strtoll(buf + ts_node_start_byte(a), NULL, 10)
		     + strtoll(buf + ts_node_start_byte(b), NULL, 10);
	}
	return bench_report(ok, len, count, sum, ms);
}
