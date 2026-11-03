/* typst.c: Markdown to Typst, from the tape that corpus/markdown/markdown.hbnf makes.

   Build:  hbnf corpus/markdown/markdown.hbnf --backend=c --layout=tape > md.c
           cat md.c corpus/markdown/typst.c > m.c && cc -O2 -Iruntime -DOUT_T=document_t m.c -o md2typst
   Use:    md2typst file.md > file.typ

   The parser is the grammar and nothing else; this file only walks the tape it wrote.  A tape is a
   flat run of words: a node that holds others says where the run after it ends, a text says where it
   is in the input.  So a node is `kids(i)` to `end(i)`, and a text is a slice of the input. */
#include <stdio.h>
#include <string.h>
#include <ctype.h>

static const char *src;                  /* the input, with its last line feed */

/* ---- the tape, as the walker sees it */
typedef struct { int tag; size_t end; const char *s; size_t n; size_t next; } Node;

static Node node (size_t i)
{
    uint64_t w = tape[i];
    Node r = { (int) (w >> 56), 0, 0, 0, i + 1 };
    if (TAPE_IS_OPENER (r.tag)) r.end = w & ((1ull << 40) - 1);
    else if (TAPE_IS_TEXT (r.tag)) {
        size_t len = (w >> 40) & 0xFFFF;
        if (len == TAPE_LONG) len = tape[r.next++];
        r.s = src + (w & ((1ull << 40) - 1));
        r.n = len;
    }
    return r;
}
/* where the node at i ends: past its kids if it holds any, else past itself */
static size_t after (size_t i) { Node r = node (i); return TAPE_IS_OPENER (r.tag) ? r.end : r.next; }

/* ---- the output, indented on demand: a line gets its indent when something is written on it */
static int ind, at_bol = 1, at_ls = 1;   /* indent now; nothing written on this line; text starts a line */
static int pend, lead, raw;                  /* spaces held back, so a line end or a closing bracket drops them; drop spaces now */

static void put (const char *s, size_t n)
{
    for (size_t k = 0; k < n; k++) {
        if (s[k] == '\n') { pend = 0; putchar ('\n'); at_bol = 1; continue; }
        if (s[k] == ' ' && !raw) { if (!lead && !at_bol) pend++; continue; }
        if (at_bol) { printf ("%*s", ind, ""); at_bol = 0; }
        for (; pend; pend--) putchar (' ');
        lead = 0;
        putchar (s[k]);
    }
}
static void puts_ (const char *s) { put (s, strlen (s)); }
static void blank (void) { if (!at_bol) puts_ ("\n"); puts_ ("\n"); at_ls = 1; }
static void drop_spaces (void) { pend = 0; }

/* text: what Typst reads as markup is written with a backslash.  At the start of a line also the
   marks of a heading, a list and a term (= - + / and a number with a stop). */
static void text (const char *s, size_t n)
{
    for (size_t k = 0; k < n; k++) {
        char c = s[k];
        if (at_ls && c != ' ') {
            if (strchr ("=-+/", c)) put ("\\", 1);
            else if (isdigit ((unsigned char) c)) {
                size_t j = k; while (j < n && isdigit ((unsigned char) s[j])) j++;
                if (j < n && (s[j] == '.' || s[j] == ')')) { put (s + k, j - k); put ("\\", 1); k = j - 1; at_ls = 0; continue; }
            }
            at_ls = 0;
        }
        if (strchr ("\\#$*_`<>@[]~", c)) put ("\\", 1);
        put (&c, 1);
    }
}
/* a string of Typst: "..." with \ and " escaped */
static void str (const char *s, size_t n)
{
    put ("\"", 1);
    for (size_t k = 0; k < n; k++) { if (s[k] == '"' || s[k] == '\\') put ("\\", 1); put (s + k, 1); }
    put ("\"", 1);
}

/* ---- inline marks */
static void inlines (size_t i, size_t end);

static void inline_ (Node v)
{
    const char *p, *q;
    switch (v.tag) {
    case T_text: case T_lone:  text (v.s, v.n); break;
    case T_escape:             text (v.s + 1, v.n - 1); break;
    case T_code_span:          put (v.s, v.n); at_ls = 0; break;                  /* `x` is the same raw text in Typst */
    case T_strong:             puts_ ("*"); inlines (v.next, v.end); puts_ ("*"); break;
    case T_emph:               puts_ ("_"); inlines (v.next, v.end); puts_ ("_"); break;
    case T_strike:             puts_ ("#strike["); inlines (v.next, v.end); puts_ ("]"); break;
    case T_autolink:           puts_ ("#link("); str (v.s + 1, v.n - 2); puts_ (")"); break;
    case T_image:              /* ![alt](src "title") */
        p = memchr (v.s, ']', v.n); q = p + 2;
        puts_ ("#image("); { size_t m = 0; while (q + m < v.s + v.n - 1 && q[m] != ' ') m++; str (q, m); }
        puts_ (", alt: "); str (v.s + 2, p - (v.s + 2)); puts_ (")"); break;
    case T_link: {             /* inlines, then the destination: a url and perhaps a title */
        size_t d = v.next, last = d;
        while (d < v.end) { last = d; d = after (d); }
        Node dest = node (last); size_t m = 0;
        while (m < dest.n && dest.s[m] != ' ') m++;
        puts_ ("#link("); str (dest.s, m); puts_ (")[");
        inlines (v.next, last); puts_ ("]"); break;
    }
    }
    at_ls = 0;
}
static void inlines (size_t i, size_t end) { while (i < end) { Node v = node (i); inline_ (v); i = after (i); } }

/* a line of inlines; Typst reads a line end as a space, so the lines stay lines; a space at the end goes */
static void line (Node v)
{
    inlines (v.next, v.end);
}

/* ---- blocks */
static void blocks (size_t i, size_t end, int tight);

/* a row's cells, each in [ ], with the separator after the last as the caller says */
static void cells (Node r)
{
    for (size_t c = r.next; c < r.end; c = after (c)) {
        Node cell = node (c);
        puts_ ("["); at_ls = 0; lead = 1; inlines (cell.next, cell.end); drop_spaces (); lead = 0;
        puts_ (after (c) < r.end ? "], " : "]");
    }
}

static void table (Node v)
{
    char buf[32];
    Node h = node (v.next); size_t cols = 0, i = after (v.next);
    for (size_t c = h.next; c < h.end; c = after (c)) cols++;
    Node d = node (i);
    puts_ ("#table(\n"); ind += 2;
    snprintf (buf, sizeof buf, "columns: %zu,\n", cols); puts_ (buf);
    if (d.tag == T_delimiter) {                  /* |:--|--:|:-:| names the alignment of each column */
        size_t k = 0, col = 0; puts_ ("align: (");
        while (k < d.n) {
            while (k < d.n && d.s[k] != ':' && d.s[k] != '-') k++;
            if (k >= d.n) break;
            int l = d.s[k] == ':';
            while (k < d.n && (d.s[k] == ':' || d.s[k] == '-')) k++;
            int r = d.s[k - 1] == ':';
            if (col++) puts_ (", ");
            puts_ (l && r ? "center" : r ? "right" : "left");
            while (k < d.n && d.s[k] != '|') k++;
        }
        puts_ ("),\n"); i = after (i);
    }
    puts_ ("table.header("); cells (h); puts_ ("),\n");
    for (; i < v.end; i = after (i)) { cells (node (i)); puts_ (",\n"); }
    ind -= 2; puts_ (")");
}

static void list (Node v)
{
    int prev = -1;
    for (size_t i = v.next; i < v.end; i = after (i)) {
        Node it = node (i), mk = node (it.next);
        int ordered = isdigit ((unsigned char) mk.s[0]);
        size_t w = ordered ? mk.n + 1 : 2;
        if (i != v.next) { puts_ ("\n"); if (ordered != prev) puts_ ("\n"); }
        prev = ordered;
        if (ordered) { put (mk.s, mk.n); put (" ", 1); } else puts_ ("- ");
        ind += (int) w; at_ls = 1;
        blocks (after (it.next), it.end, 1);
        ind -= (int) w;
    }
}

static void fence (Node v)
{
    size_t i = v.next, run = 3, n;
    Node f = node (i); const char *info = ""; size_t infon = 0;
    if (f.tag == T_info) { info = f.s; infon = f.n; while (infon && *info == ' ') { info++; infon--; } i = f.next; }
    /* the ticks round the code are one more than the longest run inside it */
    for (size_t c = i; c < v.end; c = after (c)) {
        Node l = node (c); size_t r = 0;
        for (size_t k = 0; k < l.n; k++) { r = l.s[k] == '`' ? r + 1 : 0; if (r >= run) run = r + 1; }
    }
    for (n = 0; n < run; n++) put ("`", 1);
    put (info, infon); puts_ ("\n");
    raw = 1;
    for (size_t c = i; c < v.end; c = after (c)) { Node l = node (c); put (l.s, l.n); puts_ ("\n"); }
    raw = 0;
    for (n = 0; n < run; n++) put ("`", 1);
}

static void quote (Node v)
{
    puts_ ("#quote(block: true)[\n"); ind += 2;
    for (size_t i = v.next; i < v.end; i = after (i)) { at_ls = 1; line (node (i)); puts_ ("\n"); }
    ind -= 2; puts_ ("]");
}

static void blocks (size_t i, size_t end, int tight)
{
    int first = 1;
    while (i < end) {
        Node v = node (i);
        if (!first) { if (tight && v.tag == T_list) puts_ ("\n"); else blank (); }
        first = 0; at_ls = 1;
        switch (v.tag) {
        case T_heading: {
            Node h = node (v.next); for (size_t k = 0; k < h.n; k++) puts_ ("=");
            puts_ (" "); at_ls = 0; inlines (h.next, v.end); break; }
        case T_paragraph: {
            int firstline = 1;
            for (size_t c = v.next; c < v.end; c = after (c)) {
                if (!firstline) { puts_ ("\n"); at_ls = 1; }
                firstline = 0; line (node (c));
            }
            break; }
        case T_rule:     puts_ ("#line(length: 100%)"); break;
        case T_quote:    quote (v); break;
        case T_fence:    fence (v); break;
        case T_list:     list (v); break;
        case T_table:    table (v); break;
        }
        i = after (i);
    }
}

int main (int argc, char **argv)
{
    FILE *f = fopen (argv[1], "rb"); fseek (f, 0, SEEK_END); long n = ftell (f); rewind (f);
    char *buf = malloc (n + 18); fread (buf, 1, n, f); fclose (f);
    if (n == 0 || buf[n - 1] != '\n') buf[n++] = '\n';     /* the grammar ends a line with a line feed */
    memset (buf + n, 0, 17);
    src = buf;
    OUT_T v; char err[512]; size_t l, c;
    if (!parse_text (buf, &v, err, sizeof err, &l, &c)) { fprintf (stderr, "%s:%zu:%zu: %s\n", argv[1], l, c, err); return 1; }
    Node d = node (0);                                      /* the document */
    blocks (d.next, d.end, 0);
    puts_ ("\n");
    return 0;
}
