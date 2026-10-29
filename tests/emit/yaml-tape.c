/* yaml-tape.c: a driver for corpus/yaml/yaml-tape.hbnf; the generated parser is included above it.
   It prints the tape, a word to a line as "tag length-or-link start", for yaml-tape.py. */
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    char *buf = malloc(n + 17); fread(buf, 1, n, f); fclose(f); memset(buf + n, 0, 17);
    char err[512]; size_t l, c; yaml_t v = 0; size_t i;
    if (!parse_text(buf, &v, err, sizeof err, &l, &c)) { printf("error\n"); return 1; }
    printf("tape\n");
    for (i = 0; i < tape_n; i++) {
        uint64_t w = tape[i], t = w >> 56, len = (w >> 40) & 0xFFFF, at = w & ((1ull << 40) - 1);
        if (TAPE_IS_OPENER(t)) printf("%d link %llu\n", (int) t, (unsigned long long) at);
        else if (TAPE_IS_TEXT(t)) {
            if (len == TAPE_LONG) len = tape[++i];
            printf("%d text %llu %llu\n", (int) t, (unsigned long long) at, (unsigned long long) len);
        } else printf("%d\n", (int) t);
    }
    return 0;
}
