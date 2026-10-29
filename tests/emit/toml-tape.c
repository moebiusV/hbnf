/* toml-tape.c: a driver for corpus/toml/toml-tape.hbnf; the generated parser is included above it.
   It counts the values of each kind on the tape and checks each text points inside the input and
   each link stays inside the tape and past its own word. */
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    char *buf = malloc(n + 17); fread(buf, 1, n, f); fclose(f); memset(buf + n, 0, 17);
    char err[512]; size_t l, c; toml_t v = 0;
    if (!parse_text(buf, &v, err, sizeof err, &l, &c)) { printf("error %zu:%zu\n", l, c); return 1; }
    size_t cnt[16] = {0}, i;
    for (i = 0; i < tape_n; i++) {
        uint64_t w = tape[i], t = w >> 56, len = (w >> 40) & 0xFFFF, at = w & ((1ull << 40) - 1);
        if (t < T_TABLE || t > T_KEY) { printf("bad tag at %zu\n", i); return 3; }
        cnt[t]++;
        if (TAPE_IS_OPENER(t)) {
            if (at <= i || at > tape_n) { printf("bad link at %zu\n", i); return 3; }
        } else if (TAPE_IS_TEXT(t)) {
            if (len == TAPE_LONG) len = tape[++i];
            if (len == 0 || at + len > (uint64_t) n) { printf("text leaves the input at %zu\n", i); return 3; }
        }
    }
    printf("table %zu atable %zu keyval %zu arr %zu inl %zu str %zu int %zu float %zu bool %zu date %zu key %zu\n",
        cnt[T_TABLE], cnt[T_ATABLE], cnt[T_KEYVAL], cnt[T_ARR], cnt[T_INL], cnt[T_STR], cnt[T_INT],
        cnt[T_FLOAT], cnt[T_TRUE] + cnt[T_FALSE], cnt[T_DATE], cnt[T_KEY]);
    return 0;
}
