/* dump.c: a driver for a grammar made with --layout=tape; the generated parser is included above it
   (compiled with -DOUT_T=<the root's type>).  It prints the tape, a line to a node, naming each by its
   rule, for layout.sh and json-counts.py, and checks the tape holds together: every tag is a node of the
   grammar's, every link is past its own word and inside the tape, every text is inside the input. */
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    char *buf = malloc(n + 17); fread(buf, 1, n, f); fclose(f); memset(buf + n, 0, 17);
    char err[512]; size_t l, c, i;
    OUT_T v;
    if (!parse_text(buf, &v, err, sizeof err, &l, &c)) { printf("error\n"); return 1; }
    printf("tape\n");
    for (i = 0; i < tape_n; i++) {
        uint64_t w = tape[i], t = w >> 56, len = (w >> 40) & 0xFFFF, at = w & ((1ull << 40) - 1);
        if (t == 0 || t >= sizeof tape_tag_names / sizeof *tape_tag_names) { printf("bad tag at %zu\n", i); return 3; }
        if (TAPE_IS_OPENER(t)) {
            if (at <= i || at > tape_n) { printf("bad link at %zu\n", i); return 3; }
            printf("%s\n", tape_tag_names[t]);
        } else if (TAPE_IS_TEXT(t)) {
            if (len == TAPE_LONG) len = tape[++i];
            if (at + len > (uint64_t) n) { printf("text leaves the input at %zu\n", i); return 3; }
            printf("%s %.*s\n", tape_tag_names[t], (int) len, buf + at);
        } else printf("%s %llu\n", tape_tag_names[t], (unsigned long long) at);
    }
    return 0;
}
