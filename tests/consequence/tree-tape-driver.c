/* tree-tape-driver.c: parses the two texts on the command line with the grammar (layout tape, -DROOT_T=the root's type) and
   says whether their tapes are the same: each word as its tag and, for a text, the string it names.  A text is read with
   tape_text_ptr: from the input, or from the tape itself where a `->` wrote the text of a template there. */
#include <stdio.h>
#include <string.h>

static void canon(const char *input, char *buf, size_t cap) {
    size_t i, o = 0;
    for (i = 0; i < tape_n && o + 200 < cap; i++) {
        uint64_t w = tape[i];
        unsigned tag = (unsigned)(w >> 56);
        const char *name = tape_tag_names[tag];
        if (TAPE_IS_TEXT(tag)) {
            size_t n, words;
            const char *s = tape_text_ptr(tape, i, input, &n, &words);
            o += (size_t)snprintf(buf + o, cap - o, "%s=%.*s;", name, (int)n, s);
            i += words - 1;
        } else if (TAPE_IS_OPENER(tag)) {
            o += (size_t)snprintf(buf + o, cap - o, "(%s;", name);
        } else {
            o += (size_t)snprintf(buf + o, cap - o, "%s:%llu;", name, (unsigned long long)(w & 0xFFFFFFFFFFull));
        }
    }
    buf[o] = 0;
}

static int one(const char *t, char *buf, size_t cap) {
    ROOT_T v;
    char err[256];
    size_t l, c;
    tape_n = 0;
    if (!parse_text(t, &v, err, sizeof err, &l, &c)) { snprintf(buf, cap, "error"); return 0; }
    canon(t, buf, cap);
    return 1;
}

int main(int argc, char **argv) {
    char a[4096], b[4096];
    int ra, rb;
    if (argc < 3) return 2;
    ra = one(argv[1], a, sizeof a);
    rb = one(argv[2], b, sizeof b);
    if (!ra && !rb) puts("error");
    else if (ra && rb && strcmp(a, b) == 0) puts("same");
    else printf("different: %s | %s\n", a, b);
    return 0;
}
