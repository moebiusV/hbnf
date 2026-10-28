/* json-tape.c: a driver for corpus/json/json-tape.hbnf; the generated parser is included above it */
#include <time.h>
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb"); fseek(f, 0, SEEK_END); long n = ftell(f); rewind(f);
    char *buf = malloc(n + 17); fread(buf, 1, n, f); fclose(f); memset(buf + n, 0, 17);
    int reps = argc > 2 ? atoi(argv[2]) : 1;
    char err[512]; size_t l, c; json_t v = 0; bool ok = false;
    struct timespec a, b; double best = 1e9;
    for (int r = 0; r < reps; r++) {
        tape_n = 0; tape_text = buf;
        clock_gettime(CLOCK_MONOTONIC, &a);
        ok = parse_text(buf, &v, err, sizeof err, &l, &c);
        clock_gettime(CLOCK_MONOTONIC, &b);
        double t = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
        if (t < best) best = t;
    }
    if (!ok) { printf("error %zu:%zu\n", l, c); return 1; }
    size_t cnt[9] = {0};
    for (size_t i = 0; i < tape_n; i += 2) cnt[tape[i]]++;
    printf("obj %zu arr %zu str %zu num %zu true %zu false %zu null %zu key %zu tape %zu words best %.3f ms\n",
        cnt[1], cnt[2], cnt[3], cnt[4], cnt[5], cnt[6], cnt[7], cnt[8], tape_n, best);
    return 0;
}
