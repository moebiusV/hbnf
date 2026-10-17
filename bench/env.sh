#!/bin/sh
# env.sh — one line saying what the numbers were measured on and with.
cpu=$(awk -F: '/model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo)
cores=$(awk '/^processor/ {n++} END {print n}' /proc/cpuinfo)
tools="gcc $(gcc -dumpversion)"
tools="$tools, byacc $(byacc -V 2>&1 | head -1 | awk '{print $NF}'), $(bison --version | head -1 | sed 's/.*(GNU Bison) /bison /'), $(flex --version | sed 's/flex /flex /')"
tools="$tools, peg/leg $(leg -V 2>&1 | head -1 | sed 's/.*version //')"
tools="$tools, tree-sitter $(tree-sitter --version 2>&1 | head -1 | awk '{print $2}')"
tools="$tools, ANTLR 4.13.2 on $(java -version 2>&1 | head -1 | sed 's/openjdk version //; s/\"//g')"
rev=${HOST_REV:-unknown}
printf 'Measured %s on %s (%s threads), load %s on the host, hbnf %s; %s; best of %s runs, one process per run, `gcc -O2`.\n' \
	"$(date +%F)" "$cpu" "${HOST_CPUS:-$cores}" "${HOST_LOAD:-?}" "$rev" "$tools" "${RUNS:-5}"
