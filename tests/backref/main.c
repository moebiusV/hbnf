/* Back-references: a closing tag repeats the opening one. */
#include <stdio.h>
#include <string.h>

static void run(const char *text) {
    ROOT out; char err[256], *nl; size_t l, c;
    int r = parse_text(text, &out, err, sizeof err, &l, &c);
    if (!r && (nl = strchr(err, '\n'))) *nl = 0;
    printf("%-26s %s\n", text, r ? "accepted" : err);
}
int main(void) {
    run("<a></a>");
    run("<a>text</a>");
    run("<a><b></b></a>");
    run("<a><a></a></a>");
    run("<a></a><b></b>");
    run("x<a>y<b>z</b>w</a>v");
    run("<a></b>");
    run("<a><b></a></b>");
    run("<ab></a>");
    run("<a></ab>");
    run("<a>");
    run("</a>");
    return 0;
}
