/* Reads a JSON file, parses it with corpus/json/json-tape-values.hbnf's parser, and prints the tape as text, one
   line a value, in document order: obj, arr, key TEXT, str TEXT, int N, dbl %.17g, true, false, null.  Built after
   the generated parser (cat parser.c values-main.c), with -Iruntime. */
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    FILE *f = fopen(argv[1], "rb");
    long len;
    char *buf, err[256];
    size_t line, col, i;
    json_t out;
    if (!f) return 2;
    fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
    buf = (char *)malloc((size_t)len + 1);
    if (fread(buf, 1, (size_t)len, f) != (size_t)len) return 2;
    buf[len] = 0; fclose(f);
    tape_reserve((size_t)len);
    if (!parse_text(buf, &out, err, sizeof err, &line, &col)) { printf("refused: %s\n", err); return 1; }
    for (i = 0; i < tape_n; i++) {
        uint64_t w = tape[i], t = w >> 56, n = (w >> 40) & 0xFFFF, at = w & ((1ULL << 40) - 1);
        switch (t) {
        case T_OBJ: puts("obj"); break;
        case T_ARR: puts("arr"); break;
        case T_TRUE: puts("true"); break;
        case T_FALSE: puts("false"); break;
        case T_NULL: puts("null"); break;
        case T_INT: printf("int %lld\n", (long long)(int64_t)tape[++i]); break;
        case T_DBL: { double d; memcpy(&d, &tape[++i], 8); printf("dbl %.17g\n", d); break; }
        case T_STR: case T_KEY: case T_STRU: case T_KEYU: {
            const char *base = (t == T_STR || t == T_KEY) ? buf + at + 1 : tape_sb + at;
            if (n == TAPE_LONG) n = tape[++i];
            if (t == T_STR || t == T_KEY) n -= 2;
            printf("%s ", (t == T_KEY || t == T_KEYU) ? "key" : "str");
            fwrite(base, 1, n, stdout);
            putchar('\n');
            break;
        }
        }
    }
    return 0;
}
