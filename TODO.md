# What is left to implement or fix (2026-11-05)

Written at the pause; to be annotated for direction and priorities.  Each item has a `Prio:` and a `Note:` line to fill in.
Sources: CONTEXTS.md (status table and section 26, the reader and generator findings by number), RFCPLAN.md, the memory notes,
the agents' hand-backs of 2026-11-04.  Where an item is a number like "26/34" it is the item of CONTEXTS.md section 26.

State at the pause: `main` is pushed through 4bb4e9a, with two local commits after it (the notation figures, and the documents)
that are pushed with this file.  The static `./hbnf` is built from the sources of 9884a84 (the old one is `./hbnf.old`).
The speed agent is paused with its worktree intact (`.claude/worktrees/agent-a62ce11167790e13f`).

---

## 1. Benchmarks that are not current

| what | state | to do |
|---|---|---|
| `bench/libs.sh` JSON, TOML, YAML rows | from the last quiet run, before the SSE2 loop, the arena sized from the input and the context-set hash | rerun the whole of it **on a quiet machine** (`sh bench/libs.sh`, 30 min; accept only if the YAML probe reads 8.4-9.6 ms before and after and the reference rows reproduce: simdjson 1.7, RapidJSON 5.0, tomlc17 36-38, rapidyaml 15-18, libyaml 37-41) |
| `bench/libs.sh` XML rows | **interim, busy machine** (probe 18.3-19 ms), XML only, at 4bb4e9a: hbnf tape 3.67 ms, tree 5.00 ms, libxml2 SAX2 5.33; the footnote says so | the same rerun replaces them; the hbnf rows are probably 20-30% high |
| `bench/cspeed.sh` (C11 parser vs `gcc -fsyntax-only`), `bench/run.sh` stages (yacc, peg, tree-sitter, ANTLR, ntpd, pfctl, corpus), `bench/scalar.sh` | results dated 2026-10-24 to 10-27, before this month's generator changes | rerun on a quiet machine; `sh bench/run.sh --quick` first to see that it still builds |
| `bench/tokens.sh` | **broken here**: it empties `bench/results/tokens.md` (28 lines) and prints nothing, probably the tokenizers are not installed; I restored the file from git | find why, fix, rerun |
| `bench/notation.sh` | rerun 2026-11-05, current | - |
| `bench/xml-conformance.sh` | current: hbnf 34 of 34, 11 of 11 with the real generator; reruns by itself when a parser's version, the case set, or hbnf's grammar or generator changes | grow the case set (encodings, DOCTYPE forms, namespaces) |
| THP and the arena | the arena patch (9884a84) saves page faults only when the kernel cannot back the arena with huge pages; the benchmark runs with THP on and sees nothing | decide whether the benchmark should also run with THP off, and say which in the table |
| `fuzzy_search` on cores 0-4 | it makes the machine unusable for timing (probe 18 ms against 9 quiet, even on idle cores: memory bandwidth) | agree a window when it is paused |

Prio:
Note:

## 2. XML

- [ ] **The other backends cannot generate the conforming XML grammar.**  Rust and Zig emit `compile_error!` (the recursion walk is C-only code), Ada no longer generates it (no contexts), tree-sitter refused it before.  Way back: a value kept with a name in a context (CONTEXTS 13) instead of code, so the check is grammar and not C.  (26/41)
- [ ] **Not checked yet, all need an entity's replacement text parsed as content when it is used** (a bounded island, CONTEXTS 27, or a stored value): the balance of markup in an entity (`<!ENTITY e "<b>">`), a `<` or an unparsed entity inside an entity's text, `&#38;#0;`, the external subset and conditional sections, namespace constraints beyond the lexical rule.  They are in `corpus/xml/tests/loose` and the README's "Not checked".
- [ ] **Speed, from the profile (64 M instructions per 2 MB parse):**
  - the failing trial at the end of each list loop: 8.6% of instructions, the biggest.  Needs the lookahead analysis to know that a leading `!( literals )` removes first bytes (`HBNF_Lookahead.Branch_First`), then a precheck at the dispatch.  **Half done in the paused worktree** (it compiled; not measured).
  - variable-size choice nodes (48 bytes where a text item needs 24; about -1.8 MB of 9.7 MB, and removes the alloc/unwind/memset around a failed alternative)
  - the name DFA fast path (`scan_qname`, 72 instructions per call, 4%)
  - fusing `&legal` into the scans (4.6%)
  - list links in arrays (memory only: -25% JSON/TOML, -19% XML)
  - automatic left-factoring through captures (26/48): the element was factored by hand and saved a millisecond; the natural spelling would pay it
  - hidden dependence of the arena patch on `MADV_POPULATE_WRITE` (Linux 5.14+); older kernels fault as before
- [ ] **Latent hazard** in the context-set hash cache (`hbnf_lh_s`, 9884a84): it assumes the text does not change between a `?!` test and the `%bind` that follows; a `%where` block that tests a temporary buffer and adds another string at the same address would hash wrongly.
- [ ] **Silent variants and rewrite rules (CONTEXTS 26/64):** build them and bench them on the XML grammar, for the readable grammar and for speed ("readable AND fast, no stone unturned").  The profile says nothing in the XML parse is output a grammar would drop, so the speed guess is "no gain"; it is a guess.
- [ ] The README claim: "fastest conforming XML parser" only after a quiet run shows it for the tree (the tape already is).

Prio:
Note:

## 3. The language and the generator (CONTEXTS section 26, by number)

Queued reader and generator fixes (the titles are the item titles):

| item | what |
|---|---|
| 1, 2 | `'c'` is `"c"`; `'\'` for a backslash |
| 3 | a lookahead over a sequence |
| 4, 5 | `hidden` and `!`/`&` over any rule in every layout; `bol`/`eol` are text for `hidden` and for rules of characters |
| 6 | `%spaces N` at the start of a repeated group reads N as lost (repro in `/home/matthew/hbnf-repro-spaces/`) |
| 7 | a pattern rule's instances are named for the pattern |
| 11, 22, 29 | a negative lookahead over a rule that ends in one; a lookahead rule inside a rule of characters always warns; a multi-character lookahead in a rule of characters |
| 13, 14, 15 | `word`; a token exception; letters in a rule of characters |
| 17, 63 | `--layout=tape` and a lookahead over a rule that writes something is refused |
| 23, 24 | a hyperrule's literal argument ignores `sensitivity string %i`; `$K` compares bytes (it keeps the case property since a4f96d9) |
| 25 | `as K` and `$K` in the same sequence but in different group alternatives |
| 26 | a rule named `text` collides with `parse_text` in Rust and Zig |
| 27, 30, 31 | islands: an island with its own `ws`; the root after `include "html.hbnf"`; `=> grammar(js)` after `<script>` |
| 28, 61 | a generator crash; the generated tree dump (`--ast-tools`, `dump_<root>`) segfaults in its recursion |
| 60 | a rule that uses an up reference and also sets numbers with `%col` |
| 37, 38, 39 | tape words of a `%bind` need slices; a regular expression whose alternatives can begin at the same byte; `%where`/`%bind` in a layout with emits |
| 9, 10, 12, 18, 19, 20, 32, 33 | the per-backend items (Ada, Rust, tree-sitter) |

Open decisions and unbuilt designs:

- [ ] The spellings `%label`, `%num`, `%action` and the rest (reserved words without `%`): open (CONTEXTS 10).
- [ ] `col` (0-based?) and `where (cond)` as a postfix: proposed, to be confirmed (24).
- [ ] Facts (a rule's own attributes keyed by name): decided yes, nothing built (13).
- [ ] Labels (`name:` lines that set the context): open (16).
- [ ] Switch phase 2 (token and scalar overrides: decimal comma, per-region reserved words) and phase 3 (phrase variants in `ast`, the tape case): designed, not built (22).
- [ ] `=>` as the one arrow: consequence of a match (value, fact, grammar switch); decided 2026-11-02, nothing built.
- [ ] Bounded island `js.program in $R`.
- [ ] `hidden` directive, tagged union, a bench under 30 s per parser (memory: bench speed and hidden).
- [ ] Error recovery and restarts, with the Common Lisp restart system as the model (idea; not started).
- [ ] GLR: allowed by the scope note, pay only for what is used; not started.
- [ ] Granular check reporting: per-item results (backend / arch / grammar / suite), sequential, easy to run one item.
- [ ] The conf glue (`--conf`) out of the templates into an included C header.
- [ ] **Port the C-only features to Rust, Zig, Ada, tree-sitter** (the standing rule is C first, then the rest): `as K`/`$K`, up references, `^.rule`, `bol`/`eol`, the scanned lookahead, overlay, unwind marks, the arena, the tape captures, the SSE2 loop, the context-set hash.

Prio:
Note:

## 4. Corpora (grammars)

- [ ] **COBOL** (free-format core only): 5 gaps in the scan suite against cobc, 1 in NIST (`tests/cobol/scan-baseline.txt` = 5, `nist-baseline.txt` = 1); fixed format waits for `col`; copybooks, the embedded languages (SQL, CICS, DLI, JCL), PICTURE as its own grammar.  RFCPLAN step 20 (ALGOL 68, C++, COBOL on the list; IMP72 cancelled).
- [ ] **HTML**: the places where the grammar and html5lib differ (`corpus/html/tests/oracle-stricter/`: documents html5lib refuses and the grammar accepts); JS and CSS as islands (CONTEXTS 27); the island 26/27, 30, 31 items above.
- [ ] **JavaScript** (ECMAScript 2023, Script and Module) and **CSS** (Syntax 3, Selectors 4): known gaps against V8 / tinycss2 (see their READMEs).
- [ ] **SGML** and **GraphQL**: no oracle.
- [ ] **Markdown to Typst** (`corpus/markdown`): a subset of CommonMark with tables; the `%spaces` bug (26/6).
- [ ] ALGOL 68, C++ grammars: not started.
- [ ] The C compiler: action/emit into LLVM ORC and liblld, as in the IMP72 project, then c79 to facetlang: not started.

Prio:
Note:

## 5. Documents

- [ ] `HISTORY.draft.md`, `RESUME-9b.md`, `RESUME-9c.md` (untracked): fold into HISTORY.md or delete.
- [ ] `HyperBNF as leverage for LLMs` (the stated purpose): keep it written where it is and do not over-claim (memory note).
- [ ] After the quiet rerun: README, WHY.md, HISTORY.md benchmark blocks are generated by `sh bench/update-docs.sh`; the hand-written prose around the XML table (README "JSON, TOML, YAML and XML against the parsers people use") should be re-read against the new numbers.
- [ ] CONTEXTS.md is reviewed; keep the status table up to date with each decision (last 2026-11-05).

Prio:
Note:

## 6. Housekeeping on this machine

- [ ] 165 `core.*` files (124 MB) untracked in the repository root; `hbnf-*.tar.gz` files and `hbnf15.txt` untracked there too.  Delete or move out; add to `.gitignore`.
- [ ] Docker: 40 containers (340 GB, all but one stopped) and 17 GB of unused images are reclaimable; some may be yours (not touched).  `/` is 67% full (591 GB free).
- [ ] `/home/matthew/hbnf-build` is 21 GB of dev generators (`bin/hbnf-*`) and scratch (`xw`, `xcb*`, `x2`, `rel`); `.claude/worktrees` is 594 MB (the paused speed agent's among them).
- [ ] `tests/results/` is root-owned from container runs, so a host `tests/check.sh` cannot write there: run the suites in the container (as the agents did) or fix the ownership.
- [ ] `./hbnf.old` (the pre-9884a84 static generator) can go once the next rebuild is verified.
- [ ] `tests/xml/__pycache__` is left by the container.

Prio:
Note:

## 7. Questions for you

1. Is "fastest conforming XML parser" the headline, or the tape / typed-tree pair stated separately?
2. Should the benchmark run with transparent huge pages off as well as on?
3. May `fuzzy_search` be paused for one 30-minute window (the whole of `libs.sh`)?
4. Silent variants and rewrite rules: before or after the failing-trial work?
5. Which of the other backends is to be brought back to the XML grammar first: Rust, Zig or Ada?
