#!/bin/sh
# run.sh — the performance comparison, from one command.
#
#   sh bench/run.sh [--quick] [--only=hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus,rustcorpus,zigada,formats]
#
# Writes bench/results/<name>.md, one markdown table each, and env.md.  Nothing
# else produces a figure: bench/update-docs.sh copies these files into the
# documents.  Outside the container this builds the `hbnf-bench` image (a
# derived image; the toolchain image is not changed) and runs itself inside.
#
#   HBNF=/path/to/hbnf   the generator to measure (default: ./hbnf)
#
# --quick: 100,000 rules only, best of three.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

QUICK=0
ONLY=hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus,rustcorpus,zigada,formats
for a in "$@"; do
	case $a in
	--quick) QUICK=1 ;;
	--only=*) ONLY=${a#--only=} ;;
	*) echo "usage: run.sh [--quick] [--only=a,b]" >&2; exit 2 ;;
	esac
done

if [ "${BENCH_IN_CONTAINER:-}" != 1 ]; then
	. "$here/pins.txt"
	if ! docker image inspect hbnf-bench > /dev/null 2>&1; then
		docker build -t hbnf-bench -f "$here/Dockerfile" \
			--build-arg ANTLR_URL="$ANTLR_URL" --build-arg ANTLR_SHA="$ANTLR_SHA" \
			--build-arg PEG_URL="$PEG_URL" --build-arg PEG_SHA="$PEG_SHA" \
			--build-arg TS_VERSION="$TS_VERSION" "$here" || exit 1
	fi
	hb=${HBNF:-$root/hbnf}
	[ -x "$hb" ] || { echo "run.sh: no generator at $hb (set HBNF=)" >&2; exit 1; }
	load=$(cut -d' ' -f1 /proc/loadavg)
	rev=$(cd "$root" && git rev-parse --short HEAD 2> /dev/null || echo unknown)
	exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
		-v "$root:/w" -w /w \
		-v "$(dirname "$hb"):/hbnf-bin:ro" \
		-e BENCH_IN_CONTAINER=1 -e HBNF=/hbnf-bin/$(basename "$hb") \
		-e HOST_LOAD="$load" -e HOST_REV="$rev" -e HOST_CPUS="$(nproc)" \
		hbnf-bench sh /w/bench/run.sh "$@"
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
[ "$ONLY" = hbnf,yacc,peg,treesitter,antlr,ntpd,pfctl,corpus,rustcorpus,zigada,formats ] && rm -rf "$RESULTS/rows" "$RESULTS/vals" "$RESULTS/values.txt"
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
