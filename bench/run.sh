#!/bin/sh
# run.sh — the performance comparison, from one command.
#
#   sh bench/run.sh [--quick] [--only=hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus,rustcorpus,zigada]
#
# The default run measures the C parsers.  The Rust, Zig and Ada stages (rustcorpus, zigada) are run
# by naming them; they are for the benchmark of the four backends, later.
#
# Writes bench/results/<name>.md, one markdown table each, and env.md.  Nothing
# else produces a figure: bench/update-docs.sh copies these files into the
# documents.  Outside the container this builds the `hbnf-bench-glibc` image (Debian, from
# Dockerfile.glibc) and runs itself inside; everything is measured on glibc.
#
#   HBNF=/path/to/hbnf   the generator to measure (default: built in the image from the sources)
#
# --quick: 100,000 rules only, best of three.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

QUICK=0
ONLY=hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus
for a in "$@"; do
	case $a in
	--quick) QUICK=1 ;;
	--only=*) ONLY=${a#--only=} ;;
	*) echo "usage: run.sh [--quick] [--only=a,b]" >&2; exit 2 ;;
	esac
done

if [ "${BENCH_IN_CONTAINER:-}" != 1 ]; then
	. "$here/pins.txt"
	IMAGE=hbnf-bench-glibc
	if ! docker image inspect $IMAGE > /dev/null 2>&1; then
		docker build -t $IMAGE -f "$here/Dockerfile.glibc" \
			--build-arg ANTLR_URL="$ANTLR_URL" --build-arg ANTLR_SHA="$ANTLR_SHA" \
			--build-arg PEG_URL="$PEG_URL" --build-arg PEG_SHA="$PEG_SHA" \
			--build-arg TS_VERSION="$TS_VERSION" --build-arg ZIG_URL="$ZIG_URL" --build-arg ZIG_SHA="$ZIG_SHA" \
			--build-arg RUSTUP_URL="$RUSTUP_URL" --build-arg RUSTUP_SHA="$RUSTUP_SHA" --build-arg RUST_VERSION="$RUST_VERSION" \
			"$here" || exit 1
	fi
	# The generator is built in the image from the repository's sources, so it runs on the libc it is
	# measured with; a build is kept in bench/cache under the hash of the sources.
	# The measuring runs on one logical cpu, the one the machine's other jobs leave alone:
	# BENCH_CPUS, default logical cpu 5.  Other users' jobs may still run there unless the core is
	# reserved (isolcpus, or `cset shield`); the load average is recorded below.
	BENCH_CPUS=${BENCH_CPUS:-5}
	hb=${HBNF:-}
	if [ -z "$hb" ]; then
		sum=$(cat "$root"/*.ads "$root"/*.adb | sha256sum | cut -c1-12)
		hb=$here/cache/hbnf-glibc-$sum
		if [ ! -x "$hb" ]; then
			mkdir -p "$here/cache"
			docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/w:ro" -v "$here/cache:/out" $IMAGE sh -c \
				"mkdir -p /tmp/b && cp /w/*.ad[sb] /tmp/b/ && cd /tmp/b && gnatmake -q -gnat2022 -gnatws -I. hbnf.adb -o /out/hbnf-glibc-$sum" \
				|| { echo "run.sh: could not build the generator in $IMAGE" >&2; exit 1; }
		fi
	fi
	[ -x "$hb" ] || { echo "run.sh: no generator at $hb (set HBNF=)" >&2; exit 1; }
	load=$(cut -d' ' -f1 /proc/loadavg)
	rev=$(cd "$root" && git rev-parse --short HEAD 2> /dev/null || echo unknown)
	docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp --cpuset-cpus="$BENCH_CPUS" \
		-v "$root:/w" -w /w \
		-v "$(dirname "$hb"):/hbnf-bin:ro" \
		-e BENCH_IN_CONTAINER=1 -e HBNF=/hbnf-bin/$(basename "$hb") \
		-e HOST_LOAD="$load" -e HOST_REV="$rev" -e HOST_CPUS="$(nproc)" \
		$IMAGE sh /w/bench/run.sh "$@"
	rc=$?
	# whatever the run measured goes into the documents, so a rebench leaves them current
	[ $rc = 0 ] && { sh "$here/update-docs.sh" || rc=$?; }
	exit $rc
fi

# ---- inside the container -------------------------------------------------
export HBNF_TEMPLATES=/w/templates
here=/w/bench
RESULTS=$here/results
mkdir -p "$RESULTS"
if [ "$QUICK" = 1 ]; then N_LIST="100000"; RUNS=3; else N_LIST="100000 1000000"; RUNS=5; fi
. "$here/lib.sh"
set -a
. "$here/pins.txt"
set +a
IN=$(mktemp -d)
trap 'rm -rf "$IN"' EXIT
export IN RESULTS N_LIST RUNS QUICK here

# The toy inputs, once; every tool reads these bytes.
for n in $N_LIST; do "$here/gen.sh" toy "$n" > "$IN/toy-$n.txt"; done

# A full run starts from nothing, so a row from an earlier run cannot leak into
# a table; --only keeps the other stages' rows.
[ "$ONLY" = hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus ] && rm -rf "$RESULTS/rows" "$RESULTS/vals" "$RESULTS/values.txt"
sh "$here/env.sh" > "$RESULTS/env.md"
rm -f "$RESULTS/stage-times.txt"

for s in $(echo "$ONLY" | tr , " " | tr " " "\n" | grep -v "^$"); do
	echo "== $s =="
	t0=$(date +%s)
	sh "$here/stage-$s.sh" || echo "stage $s: FAILED"
	echo "stage $s: $(( $(date +%s) - t0 )) s" | tee -a "$RESULTS/stage-times.txt"
done
# assemble.sh rebuilds every table from the rows on disk, so it runs only when every stage
# that leaves rows has just run; after --only=some it would overwrite the other tables with
# whatever rows the checkout happens to hold (it did: a one-stage run replaced the toy
# table's hbnf row).  A stage that writes its own table (ntpd, pfctl) needs no assembling.
full=1
for s in hbnf yacc peg treesitter antlr; do
	case ,$ONLY, in *,$s,*) ;; *) full=0 ;; esac
done
if [ "$full" = 1 ]; then
	sh "$here/assemble.sh"
else
	echo "partial run: tables of the stages not run are left as they were (assemble skipped)"
fi
echo "results in $RESULTS"
