#!/bin/sh
# update-docs.sh — put the benchmark results into the documents.
#
#   sh bench/update-docs.sh [--check] [--allow-skipped]
#
# Every block
#       <!-- bench:NAME -->
#       ...
#       <!-- /bench:NAME -->
# in WHY.md, README.md, USENIXSUBMISSION.md and HISTORY.md is replaced by
# bench/results/NAME.md.  Text outside a block is never touched, so the prose
# stays hand-written and the figures stay generated.
#
#   --check          change nothing; exit 1 if a document differs from the results
#   --allow-skipped  accept a results file with a "skipped:" row (a tool that
#                    could not be run); without it that is an error, so a
#                    missing comparator is never written up as a result
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
RESULTS=$here/results
CHECK=0; ALLOW=0
for a in "$@"; do
	case $a in
	--check) CHECK=1 ;;
	--allow-skipped) ALLOW=1 ;;
	*) echo "usage: update-docs.sh [--check] [--allow-skipped]" >&2; exit 2 ;;
	esac
done

status=0
for doc in WHY.md README.md USENIXSUBMISSION.md HISTORY.md; do
	f=$root/$doc
	[ -f "$f" ] || continue
	grep -q '<!-- bench:' "$f" || continue
	new=$(mktemp)
	awk -v results="$RESULTS" -v allow="$ALLOW" '
		BEGIN {
			while ((getline kv < (results "/values.txt")) > 0) {
				i = index(kv, "=")
				if (i > 0) val[substr(kv, 1, i - 1)] = substr(kv, i + 1)
			}
			close(results "/values.txt")
		}
		# <!-- v:NAME -->text<!-- /v --> : the figure NAME, inline
		function inline(line,    out, pre, tag, name, post, rest) {
			out = ""
			while (match(line, /<!-- v:[A-Za-z0-9_]+ -->/)) {
				pre = substr(line, 1, RSTART - 1)
				tag = substr(line, RSTART, RLENGTH)
				name = tag; sub(/^<!-- v:/, "", name); sub(/ -->$/, "", name)
				rest = substr(line, RSTART + RLENGTH)
				if (!match(rest, /<!-- \/v -->/)) break
				post = substr(rest, RSTART + RLENGTH)
				if (!(name in val)) {
					print "update-docs: no value `" name "` in bench/results/values.txt" > "/dev/stderr"
					bad = 1
					out = out pre tag substr(rest, 1, RSTART + RLENGTH - 1)
				} else {
					out = out pre tag val[name] "<!-- /v -->"
				}
				line = post
			}
			return out line
		}
		/^<!-- bench:[A-Za-z0-9_-]+ -->$/ {
			name = $0; sub(/^<!-- bench:/, "", name); sub(/ -->$/, "", name)
			path = results "/" name ".md"
			if ((getline probe < path) < 0) {
				print "update-docs: no results for block `" name "` (run bench/run.sh)" > "/dev/stderr"
				bad = 1
			}
			close(path)
			print
			print ""           # a table must follow a blank line to render on the site
			while ((getline line < path) > 0) {
				if (line ~ /skipped:/ && !allow) {
					print "update-docs: `" name "` has a skipped row: " line > "/dev/stderr"
					bad = 1
				}
				print line
			}
			close(path)
			inblock = 1
			next
		}
		/^<!-- \/bench:[A-Za-z0-9_-]+ -->$/ { inblock = 0; print ""; print; next }
		!inblock { print inline($0) }
		END { exit bad }
	' "$f" > "$new" || { rm -f "$new"; status=1; continue; }
	if cmp -s "$f" "$new"; then
		rm -f "$new"
	elif [ "$CHECK" = 1 ]; then
		echo "update-docs: $doc differs from bench/results (run bench/update-docs.sh)" >&2
		diff -u "$f" "$new" | head -20 >&2
		rm -f "$new"; status=1
	else
		cat "$new" > "$f"; rm -f "$new"
		echo "updated $doc"
	fi
done
exit $status
