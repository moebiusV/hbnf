/* html.c: Markdown to HTML, from the tape that corpus/markdown/markdown.hbnf makes.

   Build:  hbnf corpus/markdown/markdown.hbnf --backend=c --layout=tape > md.c
           cat md.c corpus/markdown/html.c > h.c && cc -O2 -Iruntime -DOUT_T=document_t h.c -o md2html
   Use:    md2html file.md > body.html                  the document as a fragment
           md2html file.md TITLE [SOURCE] > page.html   a whole page, with a title and a little style;
                                                        TITLE "-" takes the first heading; SOURCE is named
                                                        in a comment, as the file to edit
   A relative link to X.md is written as X.html, and one to README.md as index.html.

   The parser is the grammar and nothing else; this file only walks the tape it wrote, as typst.c
   does.  Nothing here reads {{ or {% specially, so a page made this way needs no Jekyll (put a
   .nojekyll file beside it) and no Liquid sees the text. */
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

/* ---- output: text is escaped, markup is written as it is */
static void esc (const char *s, size_t n)
{
    for (size_t k = 0; k < n; k++) {
        switch (s[k]) {
        case '&': fputs ("&amp;", stdout); break;
        case '<': fputs ("&lt;", stdout); break;
        case '>': fputs ("&gt;", stdout); break;
        case '"': fputs ("&quot;", stdout); break;
        default:  putchar (s[k]);
        }
    }
}

/* a link or image address: a relative .md becomes .html (README.md becomes index.html), so pages made
   from a tree of Markdown files link to each other; an address with a scheme or a lone #fragment stays */
static void href (const char *s, size_t n)
{
    size_t e = 0, k;
    while (e < n && s[e] != '#' && s[e] != '?') e++;                 /* the path ends at # or ? */
    int abs = s[0] == '#' || (n >= 2 && s[0] == '/' && s[1] == '/');
    for (k = 0; k < e && s[k] != '/'; k++) if (s[k] == ':') { abs = 1; break; }
    if (abs || e < 4 || memcmp (s + e - 3, ".md", 3) != 0) { esc (s, n); return; }
    size_t b = e - 3, base = b;                                       /* the path without .md */
    while (base > 0 && s[base - 1] != '/') base--;
    if (b - base == 6 && memcmp (s + base, "README", 6) == 0) { esc (s, base); fputs ("index", stdout); }
    else esc (s, b);
    fputs (".html", stdout);
    esc (s + e, n - e);
}

/* ---- inline marks */
static void inlines (size_t i, size_t end);

static void inline_ (Node v)
{
    const char *p, *q;
    switch (v.tag) {
    case T_text: case T_lone:  esc (v.s, v.n); break;
    case T_escape:             esc (v.s + 1, v.n - 1); break;
    case T_code_span:          fputs ("<code>", stdout); esc (v.s + 1, v.n - 2); fputs ("</code>", stdout); break;
    case T_strong:             fputs ("<strong>", stdout); inlines (v.next, v.end); fputs ("</strong>", stdout); break;
    case T_emph:               fputs ("<em>", stdout); inlines (v.next, v.end); fputs ("</em>", stdout); break;
    case T_strike:             fputs ("<del>", stdout); inlines (v.next, v.end); fputs ("</del>", stdout); break;
    case T_autolink:           fputs ("<a href=\"", stdout); href (v.s + 1, v.n - 2); fputs ("\">", stdout);
                               esc (v.s + 1, v.n - 2); fputs ("</a>", stdout); break;
    case T_image:              /* ![alt](src "title") */
        p = memchr (v.s, ']', v.n); q = p + 2;
        { size_t m = 0; while (q + m < v.s + v.n - 1 && q[m] != ' ') m++;
          fputs ("<img src=\"", stdout); href (q, m); fputs ("\" alt=\"", stdout); esc (v.s + 2, p - (v.s + 2));
          fputs ("\">", stdout); }
        break;
    case T_link: {             /* inlines, then the destination: a url and perhaps a title */
        size_t d = v.next, last = d;
        while (d < v.end) { last = d; d = after (d); }
        Node dest = node (last); size_t m = 0;
        while (m < dest.n && dest.s[m] != ' ') m++;
        fputs ("<a href=\"", stdout); href (dest.s, m); fputs ("\">", stdout);
        inlines (v.next, last); fputs ("</a>", stdout); break;
    }
    }
}
static void inlines (size_t i, size_t end) { while (i < end) { inline_ (node (i)); i = after (i); } }

/* the words of some inlines, with no marks: a page title */
static void plain (size_t i, size_t end)
{
    while (i < end) {
        Node v = node (i);
        switch (v.tag) {
        case T_text: case T_lone:  esc (v.s, v.n); break;
        case T_escape:             esc (v.s + 1, v.n - 1); break;
        case T_code_span:          esc (v.s + 1, v.n - 2); break;
        case T_strong: case T_emph: case T_strike: case T_link: plain (v.next, v.end); break;
        }
        i = after (i);
    }
}

/* ---- blocks */
static void blocks (size_t i, size_t end, int tight);

static void cells (Node r, const char *tag, const char *const *al)
{
    int col = 0;
    for (size_t c = r.next; c < r.end; c = after (c), col++) {
        Node cell = node (c);
        printf ("<%s%s>", tag, al[col]);
        inlines (cell.next, cell.end);
        printf ("</%s>", tag);
    }
}

static void table (Node v)
{
    const char *al[64]; int cols = 0;
    Node h = node (v.next); size_t i = after (v.next);
    for (size_t c = h.next; c < h.end; c = after (c)) cols++;
    for (int k = 0; k < 64; k++) al[k] = "";
    Node d = node (i);
    if (d.tag == T_delimiter) {                  /* |:--|--:|:-:| names the alignment of each column */
        size_t k = 0; int col = 0;
        while (k < d.n && col < 64) {
            while (k < d.n && d.s[k] != ':' && d.s[k] != '-') k++;
            if (k >= d.n) break;
            int l = d.s[k] == ':';
            while (k < d.n && (d.s[k] == ':' || d.s[k] == '-')) k++;
            int r = d.s[k - 1] == ':';
            al[col++] = l && r ? " style=\"text-align:center\"" : r ? " style=\"text-align:right\"" : l ? " style=\"text-align:left\"" : "";
            while (k < d.n && d.s[k] != '|') k++;
        }
        i = after (i);
    }
    fputs ("<table>\n<thead>\n<tr>", stdout); cells (h, "th", al); fputs ("</tr>\n</thead>\n<tbody>\n", stdout);
    for (; i < v.end; i = after (i)) { fputs ("<tr>", stdout); cells (node (i), "td", al); fputs ("</tr>\n", stdout); }
    fputs ("</tbody>\n</table>", stdout);
}

static void list (Node v)
{
    int open = 0;                                /* 0 none, 1 ul, 2 ol: a change of marker starts a new list */
    for (size_t i = v.next; i < v.end; i = after (i)) {
        Node it = node (i), mk = node (it.next);
        int ordered = isdigit ((unsigned char) mk.s[0]);
        int paras = 0;
        for (size_t c = after (it.next); c < it.end; c = after (c)) if (node (c).tag == T_paragraph) paras++;
        if (open != (ordered ? 2 : 1)) {
            if (open) fputs (open == 1 ? "</ul>\n" : "</ol>\n", stdout);
            if (ordered) { int num = atoi (mk.s); if (num != 1) printf ("<ol start=\"%d\">\n", num); else fputs ("<ol>\n", stdout); }
            else fputs ("<ul>\n", stdout);
            open = ordered ? 2 : 1;
        }
        fputs ("<li>", stdout);
        blocks (after (it.next), it.end, paras <= 1);
        fputs ("</li>\n", stdout);
    }
    if (open) fputs (open == 1 ? "</ul>" : "</ol>", stdout);
}

static void fence (Node v)
{
    size_t i = v.next;
    Node f = node (i);
    fputs ("<pre><code", stdout);
    if (f.tag == T_info) {
        const char *info = f.s; size_t infon = f.n;
        while (infon && *info == ' ') { info++; infon--; }
        fputs (" class=\"language-", stdout); esc (info, infon); fputs ("\"", stdout);
        i = f.next;
    }
    fputs (">", stdout);
    for (size_t c = i; c < v.end; c = after (c)) { Node l = node (c); esc (l.s, l.n); putchar ('\n'); }
    fputs ("</code></pre>", stdout);
}

static void icode (Node v)
{
    fputs ("<pre><code>", stdout);
    for (size_t c = v.next; c < v.end; c = after (c)) { Node l = node (c); esc (l.s, l.n); putchar ('\n'); }
    fputs ("</code></pre>", stdout);
}

static void quote (Node v)
{
    int firstline = 1;
    fputs ("<blockquote>\n<p>", stdout);
    for (size_t i = v.next; i < v.end; i = after (i)) {
        Node l = node (i);
        if (!firstline) putchar ('\n');
        firstline = 0; inlines (l.next, l.end);
    }
    fputs ("</p>\n</blockquote>", stdout);
}

static void blocks (size_t i, size_t end, int tight)
{
    int first = 1;
    while (i < end) {
        Node v = node (i);
        if (!first) putchar ('\n');
        first = 0;
        switch (v.tag) {
        case T_heading: {
            Node h = node (v.next); printf ("<h%zu>", h.n); inlines (h.next, v.end); printf ("</h%zu>", h.n); break; }
        case T_setext: {
            Node ln = node (v.next); Node u = node (ln.end); int lv = u.s[0] == '=' ? 1 : 2;
            printf ("<h%d>", lv); inlines (ln.next, ln.end); printf ("</h%d>", lv); break; }
        case T_paragraph: {
            int firstline = 1;
            if (!tight) fputs ("<p>", stdout);
            for (size_t c = v.next; c < v.end; c = after (c)) {
                if (!firstline) putchar ('\n');
                firstline = 0; { Node l = node (c); inlines (l.next, l.end); }
            }
            if (!tight) fputs ("</p>", stdout);
            break; }
        case T_rule:     fputs ("<hr>", stdout); break;
        case T_quote:    quote (v); break;
        case T_fence:    fence (v); break;
        case T_icode:    icode (v); break;
        case T_list:     list (v); break;
        case T_table:    table (v); break;
        }
        i = after (i);
    }
}

int main (int argc, char **argv)
{
    if (argc < 2) { fprintf (stderr, "usage: md2html file.md [TITLE|-] [SOURCE] > out.html\n"); return 2; }
    FILE *f = fopen (argv[1], "rb");
    if (!f) { perror (argv[1]); return 2; }
    fseek (f, 0, SEEK_END); long n = ftell (f); rewind (f);
    char *buf = malloc (n + 18); if (fread (buf, 1, n, f) != (size_t) n) return 2; fclose (f);
    if (n == 0 || buf[n - 1] != '\n') buf[n++] = '\n';     /* the grammar ends a line with a line feed */
    memset (buf + n, 0, 17);
    src = buf;
    OUT_T v; char err[512]; size_t l, c;
    if (!parse_text (buf, &v, err, sizeof err, &l, &c)) { fprintf (stderr, "%s:%zu:%zu: %s\n", argv[1], l, c, err); return 1; }
    Node d = node (0);                                      /* the document */
    if (argc > 2) {
        fputs ("<!doctype html>\n", stdout);
        if (argc > 3) { fputs ("<!-- generated from ", stdout); esc (argv[3], strlen (argv[3])); fputs (" by md2html; edit that file, not this one -->\n", stdout); }
        fputs ("<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
               "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>", stdout);
        if (strcmp (argv[2], "-") != 0) esc (argv[2], strlen (argv[2]));
        else {                                              /* the first heading, else the file name */
            int found = 0;
            for (size_t i = d.next; i < d.end && !found; i = after (i)) {
                Node b = node (i);
                if (b.tag == T_heading) { Node h = node (b.next); plain (h.next, b.end); found = 1; }
                else if (b.tag == T_setext) { Node ln = node (b.next); plain (ln.next, ln.end); found = 1; }
            }
            if (!found) esc (argc > 3 ? argv[3] : argv[1], strlen (argc > 3 ? argv[3] : argv[1]));
        }
        fputs ("</title>\n<style>\n"
               "body { max-width: 52rem; margin: 2rem auto; padding: 0 1rem; font: 16px/1.5 sans-serif; color: #222; background: #fff; }\n"
               "pre { background: #f4f4f4; padding: .75rem; overflow-x: auto; }\n"
               "code { background: #f4f4f4; padding: 0 .2em; }\n"
               "pre code { padding: 0; }\n"
               "table { border-collapse: collapse; }\n"
               "th, td { border: 1px solid #ccc; padding: .25rem .6rem; }\n"
               "blockquote { margin-left: 0; padding-left: 1rem; border-left: 3px solid #ccc; color: #555; }\n"
               "@media (prefers-color-scheme: dark) { body { color: #ddd; background: #181818; } pre, code { background: #262626; } th, td { border-color: #444; } }\n"
               "</style>\n</head>\n<body>\n", stdout);
    }
    blocks (d.next, d.end, 0);
    putchar ('\n');
    if (argc > 2) fputs ("</body>\n</html>\n", stdout);
    return 0;
}
