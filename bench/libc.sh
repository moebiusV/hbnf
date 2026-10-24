#!/bin/sh
# libc.sh -- the same generated C parser built against musl (the bench container's libc) and
# glibc (the host's), on the documents of stage-formats.sh.  Only the C library differs:
# the parser source is one file, compiled with the same gcc flags.
#
#   HBNF=/path/to/hbnf sh bench/libc.sh      (host; needs docker and the hbnf-bench image)
#
# Writes bench/results/libc.md.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
hb=${HBNF:-$root/hbnf}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
chmod 755 "$W"
RUNS=${RUNS:-7}
for n in json toml yaml; do
	python3 "$here/formats/gen.py" $n 2000000 > "$W/doc.$n"
done
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e HBNF_TEMPLATES=/w/templates \
	-v "$root:/w:ro" -v "$W:/o" -v "$(dirname "$hb"):/hbnf-bin:ro" hbnf-bench sh -c '
	for spec in json:json toml:toml yaml:yaml; do
		n=${spec%%:*}; r=${spec##*:}
		/hbnf-bin/'"$(basename "$hb")"' /w/corpus/$n/$n.hbnf --backend=c --root=$r > /o/$n.c
	done'
best() {   # best BIN DOC: the least parse time of RUNS runs, in ms
	i=0; b=999999
	while [ $i -lt "$RUNS" ]; do
		t=$("$@" | awk '{print $3}')
		b=$(awk -v a="$b" -v t="$t" 'BEGIN { print (t < a ? t : a) }')
		i=$((i + 1))
	done
	echo "$b"
}
for n in json toml yaml; do
	t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' "$W/$n.c")
	cat "$W/$n.c" "$here/formats/time_format.c" > "$W/$n-m.c"
	gcc -O2 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$t" "$W/$n-m.c" -o "$W/$n-glibc"
	docker run --rm --user "$(id -u):$(id -g)" -v "$W:/o" hbnf-bench \
		gcc -O2 -std=gnu11 -D_GNU_SOURCE -w "-DOUT_T=$t" /o/$n-m.c -o /o/$n-musl
done
{
	printf '| document | musl | glibc |\n|---|---:|---:|\n'
	for n in json toml yaml; do
		m=$(docker run --rm -v "$W:/o" hbnf-bench sh -c "
			b=999999; i=0
			while [ \$i -lt $RUNS ]; do
				t=\$(/o/$n-musl /o/doc.$n | awk '{print \$3}')
				b=\$(awk -v a=\$b -v t=\$t 'BEGIN { print (t < a ? t : a) }'); i=\$((i+1))
			done; echo \$b")
		g=$(best "$W/$n-glibc" "$W/doc.$n")
		printf '| %s (2 MB) | %s ms | %s ms |\n' "$n" "$m" "$g"
	done
	printf '\n_%s; musl: %s, %s; glibc: %s, %s; `-O2`, best of %s runs, hbnf %s.  The two builds use different gcc versions, as the container and the host do._\n' \
		"$(date +%F)" \
		"$(docker run --rm hbnf-bench sh -c 'ldd 2>&1 | head -1')" \
		"$(docker run --rm hbnf-bench gcc --version | head -1 | awk '{print "gcc " $NF}')" \
		"glibc $(ldd --version | head -1 | awk '{print $NF}')" "$(gcc --version | head -1 | awk '{print "gcc " $NF}')" \
		"$RUNS" "$(cd "$root" && git rev-parse --short HEAD)"
} > "$root/bench/results/libc.md"
cat "$root/bench/results/libc.md"
