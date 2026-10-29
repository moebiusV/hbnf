#!/bin/sh
# inner.sh -- inside the glibc container: preprocess the pinned C sources, keep the units gcc accepts,
# build the generated C11 parser, and time it and `gcc -fsyntax-only` over the same files.
# /w is the repository (read-only), /o the work directory holding c11.c and the three source archives.
# Prints KEY VALUE lines.
set -u
RUNS=${RUNS:-5}
cd /o
mkdir -p src pp
tar xzf lua.tgz -C src
tar xzf zlib.tgz -C src
python3 -c "import zipfile; zipfile.ZipFile('sqlite.zip').extractall('src')"
n=0; : > list
for f in src/lua-5.4.7/src/*.c src/zlib-1.3.1/*.c src/sqlite-amalgamation-3450100/sqlite3.c; do
	n=$((n + 1)); d=$(dirname "$f")
	gcc -E -P -std=gnu11 -w "-D__attribute__(x)=" "-D__asm__(x)=" "-D__asm(x)=" -I"$d" -I"$d/.." "$f" > pp/$n.i 2> /dev/null || continue
	gcc -fsyntax-only -std=gnu11 -w pp/$n.i 2> /dev/null && echo pp/$n.i >> list
done
t=$(sed -n 's/^bool parse_text(const char \*text, \(.*\) \*out,$/\1/p' c11.c)
cat c11.c /w/bench/formats/time_c.c > c11-m.c
gcc -O2 -w -std=gnu11 -D_GNU_SOURCE "-DOUT_T=$t" c11-m.c -o bin-c11 || { echo "build failed"; exit 1; }
echo "files $(wc -l < list)"
best=; for i in $(seq "$RUNS"); do
	r=$(./bin-c11 $(cat list))
	ms=${r%% *}
	if [ -z "$best" ] || [ "$(echo "$ms $best" | awk '{print ($1 < $2)}')" = 1 ]; then best=$ms; line=$r; fi
done
echo "hbnf $line"
big=$(ls -S $(cat list) | head -1)
echo "big $(stat -c %s "$big") $(./bin-c11 "$big" | awk '{print $4}')"   # bytes and peak KiB of the largest unit alone
python3 - <<'PY'
import subprocess,time
files=open('list').read().split()
best=None
for _ in range(3):
    t=0.0
    for f in files:
        a=time.perf_counter()
        subprocess.run(['gcc','-fsyntax-only','-std=gnu11','-w',f],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        t+=time.perf_counter()-a
    best=t if best is None else min(best,t)
print("gcc %.2f"%(best*1000))
PY
