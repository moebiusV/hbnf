#include <stdio.h>
#include <string.h>
/* pp [-undef] [-nostdinc] [-trigraphs] [-std=NAME] [-Idir] [-DNAME[=v]] [-UNAME] FILE: the text a preprocessor gives, on the standard output; the diagnostics on the
   standard error, one to a line as `FILE:LINE: kind: message`; a status of 1 when there were errors */
int main(int argc, char **argv) {
    const char *file = NULL;
    int i;
    for (i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (strcmp(a, "-undef") == 0) cpp_undef = 1;
        else if (strcmp(a, "-nostdinc") == 0) cpp_nostdinc = 1;
        else if (strcmp(a, "-trigraphs") == 0) cpp_trigraphs = 1;
        else if (strncmp(a, "-std=", 5) == 0) { if (!cpp_set_std(a + 5)) { fprintf(stderr, "unknown -std=%s\n", a + 5); return 2; } }
        else if (strncmp(a, "-I", 2) == 0) cpp_add_incdir(a[2] ? a + 2 : argv[++i]);
        else if (strncmp(a, "-D", 2) == 0) cpp_command_define(a[2] ? a + 2 : argv[++i]);
        else if (strncmp(a, "-U", 2) == 0) cpp_command_undef(a[2] ? a + 2 : argv[++i]);
        else if (a[0] == '-') ;
        else file = a;
    }
    FILE *f = fopen(file, "rb"); static char buf[1 << 22]; size_t n = fread(buf, 1, sizeof buf - 1, f); buf[n] = 0; fclose(f);
    OUT_T tree; char err[2048]; size_t l, c;
    cpp_file = file;
    memset(&tree, 0, sizeof tree);
    if (parse_text(buf, &tree, err, sizeof err, &l, &c)) {
        char *o = cpp_output(hbnf_rr_buf ? hbnf_rr_buf : buf, strlen(hbnf_rr_buf ? hbnf_rr_buf : buf));
        fputs(o, stdout); free(o);
        return cpp_errors ? 1 : 0;
    }
    fprintf(stderr, "bad\n%s\n", err); return 1;
}
