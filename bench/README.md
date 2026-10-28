# bench — the performance comparison

One command measures hbnf's generated parsers against the tools it is usually
compared with, and writes the tables that `WHY.md`, `README.md` and
`USENIXSUBMISSION.md` quote.  No figure in those documents is typed by hand.

    sh bench/run.sh                  # the whole comparison (minutes; memory-hungry at 1,000,000 rules)
    sh bench/run.sh --quick          # 100,000 rules only, best of three
    sh bench/run.sh --only=yacc,ntpd # some stages (tables of the others are left alone)
    sh bench/update-docs.sh          # put bench/results/*.md into the documents
    sh bench/update-docs.sh --check  # fail if a document differs from the results

`HBNF=/path/to/hbnf sh bench/run.sh` measures that generator (default: one built in the image).
Docker is the only requirement: `run.sh` builds an image called `hbnf-bench-glibc` from
`bench/Dockerfile.glibc` (Debian, with the comparison tools; Rust from rustup, because tree-sitter needs a
newer one than Debian has) if it is absent, builds the generator inside it from the repository's sources,
and runs itself inside as you.  Everything is measured on glibc.  The default run measures the C parsers;
the Rust, Zig and Ada stages (`--only=rustcorpus,zigada`) are for the benchmark of the four backends.

## What is measured

Every stage parses the same file and builds the same information, and prints
one line, `ok BYTES COUNT SUM MS RSS_KIB`.  `COUNT` is the number of rules the
parse produced and `SUM` a checksum of their numbers; `run.sh` checks both
against what the generator wrote, and a row that is wrong says so instead of
showing a time.  Time is wall-clock around the parse call only (the file is
read first), one process per run, best of five (three with `--quick`); memory
is `getrusage`'s peak resident set.  C is compiled `gcc -O2`.

| stage | what | files |
|---|---|---|
| `hbnf` | the toy language through hbnf's C backend (`parse_text`), and pfctl's whole grammar through `parse_file` | `toy.hbnf`, `drv/hbnf_toy.c`, `time_conf.c` |
| `yacc` | the toy as flex + byacc and flex + bison, written the way a `parse.y` is (strdup'd strings, one malloc'd node per rule) | `compare/toy.l`, `compare/toy.y` |
| `peg` | the toy as a PEG with Piumarta's peg/leg | `compare/toy.leg` |
| `treesitter` | the toy as a tree-sitter grammar: a cold parse, and a re-parse after a one-byte edit with the old tree | `compare/grammar.js`, `drv/ts_toy.c` |
| `antlr` | the toy as an ANTLR 4 grammar, Java target: actions only (cold JVM, warm JVM) and the default parse tree | `compare/Toy.g4`, `compare/java/ToyMain.java` |
| `pfctl` | OpenBSD's `sbin/pfctl/parse.y` (6,546 lines) at a pinned commit, unmodified, through byacc, against hbnf's `grammars/obconf_pfctl.hbnf`; byacc fills `struct pf_rule`, hbnf builds a tree | `pfctl/` |
| `ntpd` | a real `parse.y`: OpenBSD's `usr.sbin/ntpd/parse.y` at a pinned commit, unmodified, through byacc, against hbnf's binding (`grammars/bind/ntpd.hbnf`), both filling ntpd's own `struct ntpd_conf` | `ntpd/` |

Two measurements stand outside `run.sh`, because they need no container and take seconds:
`sh bench/notation.sh` counts the rules, lines, symbols and characters of a published grammar
against the same language in HyperBNF, and `sh bench/tokens.sh` counts the same text in the
tokens of two public tokenizers (OpenAI's o200k_base and Qwen2.5's; Claude's is not public).  The
second checks that it counts the text the first counts, and fetches the tokenizers once, by the
sha256 in `pins.txt`, into `bench/cache`.

The toy is `toy.hbnf`: `pass in on em0 proto tcp from 192.168.3.7 port 51234 to
192.168.9.1 port 443`, one rule per line, the shape of a pf rule.  Inputs come
from `gen.sh` and are deterministic.

## Reading the numbers fairly

- The trees differ.  hbnf builds typed structs whose strings are slices of the
  input; yacc and PEG builds copy each string; tree-sitter builds a node per
  token with byte offsets; ANTLR's actions-only mode builds no tree at all, its
  parse-tree mode builds a generic one.  Each tool is written idiomatically for
  the task "parse this language and keep what the parse found".
- tree-sitter is built for incremental parsing of source code; the toy is a flat
  list of independent rules, which is the shape hbnf targets.  The re-parse row
  is there so a cold-parse table is not the only thing said.
- The JVM is shown cold (first parse in a fresh process) and warm (fourth parse
  in the same process); neither includes JVM start-up.
- A machine with other work on it gives slower and noisier times.  The load
  average at the start of the run is recorded under every table.
- A tool that cannot be built or run is a row that says `skipped: ...` with the
  reason.  `update-docs.sh` refuses to write such a table into a document
  unless you pass `--allow-skipped`.

## Versions and pins

`pins.txt` holds every version and hash the comparison builds against (the
ANTLR jar, peg/leg, tree-sitter, and the OpenBSD commit the ntpd sources come
from), and `ntpd/files.txt` the sha256 of each OpenBSD file.  A fetched file
that does not match its hash is not used.  The ntpd sources are cached in
`bench/cache/`, which is not committed.  To build OpenBSD's `parse.y` on Linux
without changing it, `ntpd/shim/compat.h` supplies the BSD names it expects and
`ntpd/stubs.c` the parts of ntpd it calls (logging, an address literal
"resolver", `new_sensor()`, `new_peer()`); the benchmark configs use address
literals, so no name is looked up.

## Results

`bench/results/*.md` are the tables, written by `run.sh` and committed so the
documents can be rebuilt without re-running.  A table is inserted in a document
between `<!-- bench:NAME -->` and `<!-- /bench:NAME -->`; `update-docs.sh`
rewrites what is between them and nothing else.
