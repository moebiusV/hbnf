#!/bin/sh
# build.sh -- inside the Raku container, not pinned (zef needs the network, and installing precompiles): the
# pinned grammar-based modules into /o/rakulib, a wrapper per tool in /o/bin, and the hbnf tape parsers.
# /w is the repository (read-only), /o the work directory holding the documents, the module sources
# and the hbnf tape parsers' C.  zef also fetches the modules' own dependencies (YAMLish wants MIME::Base64)
# from the ecosystem, unpinned.
set -eu
mkdir -p /o/bin /tmp/b && cd /tmp/b
for m in jsontiny toml yamlish; do
	zef install --/test --install-to="inst#/o/rakulib" /o/src/$m > /tmp/b/zef-$m.out 2>&1 || { tail -5 /tmp/b/zef-$m.out; exit 1; }
done
wrap() {   # wrap NAME SCRIPT: a command that runs one tool, a cold process each time, and says when it timed out
	cat > /o/bin/$1 <<EOS
#!/bin/sh
timeout \${RAKU_TIMEOUT:-900} raku -I "inst#/o/rakulib" /w/bench/raku/$2 "\$@"
rc=\$?
[ \$rc = 124 ] && echo "timed out after \${RAKU_TIMEOUT:-900} s" >&2
exit \$rc
EOS
	chmod +x /o/bin/$1
}
wrap json-tiny json-tiny.raku
wrap json-fast json-fast.raku
wrap toml toml.raku
wrap yamlish yamlish.raku
# the hbnf tape parsers, built as bench/haskell/build.sh builds them
for n in json toml yaml; do
	t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' /o/$n-tape.c)
	cat /o/$n-tape.c /w/bench/formats/time_tape.c > $n-tape-m.c
	gcc -O2 -w -std=gnu11 -D_GNU_SOURCE -I/w/runtime "-DOUT_T=$t" $n-tape-m.c -o /o/bin/hbnf-$n-tape
done
echo built
