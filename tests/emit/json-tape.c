/* json-tape.c: a driver for corpus/json/json-tape.hbnf; the generated parser is included above it.
   It counts the values of each kind on the tape and checks each text points at what it should
   (a string or key at its quotes, a number at a digit or a minus) and each link stays inside. */
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    char *buf = malloc(n + 17); fread(buf, 1, n, f); fclose(f); memset(buf + n, 0, 17);
    char err[512]; size_t l, c; json_t v = 0;
    if (!parse_text(buf, &v, err, sizeof err, &l, &c)) { printf("error %zu:%zu\n", l, c); return 1; }
    size_t cnt[9] = {0}, i;
    for (i = 0; i < tape_n; i++) {
        uint64_t w = tape[i], t = w >> 56, len = (w >> 40) & 0xFFFF, at = w & ((1ull << 40) - 1);
        if (t < T_OBJ || t > T_KEY) { printf("bad tag at %zu\n", i); return 3; }
        cnt[t]++;
        if (t == T_OBJ || t == T_ARR) {
            if (at <= i || at > tape_n) { printf("bad link at %zu\n", i); return 3; }
        } else if (t == T_STR || t == T_KEY || t == T_NUM) {
            if (len == TAPE_LONG) len = tape[++i];
            if (at + len > (uint64_t) n) { printf("text leaves the input at %zu\n", i); return 3; }
            if ((t == T_NUM ? !(buf[at] == '-' || (buf[at] >= '0' && buf[at] <= '9'))
                            : !(buf[at] == '"' && buf[at + len - 1] == '"'))) { printf("text misses at %zu\n", i); return 3; }
        }
    }
    printf("obj %zu arr %zu str %zu num %zu true %zu false %zu null %zu key %zu tape %zu words\n",
        cnt[1], cnt[2], cnt[3], cnt[4], cnt[5], cnt[6], cnt[7], cnt[8], tape_n);
    return 0;
}
