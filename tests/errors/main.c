/* Parse each file named on the command line and print what the parser says. */
#include <stdio.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        char err[1024];
        size_t line, col;
        static char buf[65536];
        FILE *f = fopen(argv[i], "rb");
        size_t n = f ? fread(buf, 1, sizeof buf - 1, f) : 0;
        if (f) fclose(f);
        buf[n] = 0;
        ROOT_T out;
        printf("== %s\n", argv[i]);
        if (parse_text(buf, &out, err, sizeof err, &line, &col)) puts("ok");
        else puts(err);
    }
    return 0;
}
