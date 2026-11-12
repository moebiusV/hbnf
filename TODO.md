# What is left to implement or fix (2026-11-05)

Written at the pause; to be annotated for direction and priorities.  Each item has a `Prio:` and a `Note:` line to fill in.
Sources: CONTEXTS.md (status table and section 26, the reader and generator findings by number), RFCPLAN.md, the memory notes,
the agents' hand-backs of 2026-11-04.  Where an item is a number like "26/34" it is the item of CONTEXTS.md section 26.

State at the pause: `main` is pushed through 4bb4e9a, with two local commits after it (the notation figures, and the documents)
that are pushed with this file.  The static `./hbnf` is built from the sources of 9884a84 (the old one is `./hbnf.old`).
The speed agent is paused with its worktree intact.

---

## 1. Benchmarks: all rerun on 2026-11-05, on a busy machine

Everything below was rerun at hbnf 9884a84 on a machine that was "as quiet as it will get", which is not quiet: the YAML probe read 18-19 ms
(quiet is 8.4-9.6) and the load average was 9 (`fuzzy_search` on cores 0-4, a VM).  The reference rows were compared in each footnote; no figure was adjusted.
hbnf's own rows touch many fresh pages and are the ones the load hurts most, so read them as upper bounds.

| what | state | to do |
|---|---|---|
| `bench/libs.sh` (JSON, TOML, YAML, XML), best of 9 | rerun; simdjson and rapidyaml read 20-35% high, the other references at their quiet readings; hbnf JSON tree 2.8 ms (1.9 quiet), YAML tree 12 (8.5), XML tape 3.5, tree 4.3 against libxml2 SAX2 4.8 | rerun on a quiet machine (30 min at 5 runs); accept only if the probe reads 8.4-9.6 before and after |
| `bench/cspeed.sh`, `bench/scalar.sh` | rerun (C11 tree 0.20 s, 47 MB; tape 0.12 s; gcc -fsyntax-only 0.48 s) | same |
| `bench/run.sh` (all stages: hbnf, yacc, peg, tree-sitter, ANTLR, ntpd, pfctl, corpus), which feeds WHY.md, README.md, HISTORY.md, USENIXSUBMISSION.md | rerun; the whole of it takes under 15 minutes | same |
| `bench/tokens.sh` | **fixed 2026-11-11, not rerun**: `tokens.py` stopped ("notation.md has 24 rows of figures, this has 17") because the notation table gained the tape rows, and the script had already truncated its results.  `tokens.py` now finds each of its rows in the table in order (extra rows allowed), and `tokens.sh` writes to scratch files and replaces the results only on success, saying why when it fails.  Run once, `sh bench/tokens.sh`, to refresh the figures (it ends by rewriting the benchmark blocks of README, WHY and HISTORY through `update-docs.sh`) | run it when the documents may change |
| `bench/notation.sh` | current | - |
| `bench/xml-conformance.sh` | current: hbnf 34 of 34, 11 of 11 with the real generator; reruns by itself when a parser's version, the case set, or hbnf's grammar or generator changes | grow the case set (encodings, DOCTYPE forms, namespaces) |
| THP and the arena | the arena patch (9884a84) saves page faults only when the kernel cannot back the arena with huge pages; the benchmark runs with THP on | decide whether the benchmark should also run with THP off, and say which in the table |
| `fuzzy_search` on cores 0-4 | makes the machine unusable for timing (even on idle cores: memory bandwidth) | agree a window when it is paused |

Prio:
Note:

## 2. XML

- [ ] **`tests/xml-diff.sh` fails on this machine, with the shipped `./hbnf` and with a pristine build of the same sources** (found 2026-11-11, not caused by Phase 1): the installed expat 2.7.1 accepts four bad XML declarations that hbnf refuses (`corpus/xml/tests/bad/xml-decl-version-{empty,letters,major,no-minor}.xml`, reported as `oracle accepts bad`), and expat accepts some of the random mutations hbnf refuses.  The case set was made against another expat; decide whether the oracle check should name the expat version it was made with, or skip a case the oracle's version does not refuse.
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
- [x] **Latent hazard** in the context-set hash cache (`hbnf_lh_s`, 9884a84): fixed 2026-11-11 by dropping the cache (the hash reads at most eight bytes and the length, so what it saved was a few multiplies); `tests/context/ctxhash.hbnf` asks about a buffer, overwrites it and adds, and fails on the old template.
- [ ] **Silent variants and rewrite rules (CONTEXTS 26/64):** build them and bench them on the XML grammar, for the readable grammar and for speed ("readable AND fast, no stone unturned").  The profile says nothing in the XML parse is output a grammar would drop, so the speed guess is "no gain"; it is a guess.
- [ ] The README claim: "fastest conforming XML parser" only after a quiet run shows it for the tree (the tape already is).

Prio:
Note:

## 3. The language and the generator (CONTEXTS section 26, by number)

**Done 2026-11-11 (Phase 1 of the plan):** 6, 21 (the UTF-8 half: `tests/utf8.sh`; the NUL needs a `parse_text_n`, to be settled), 28, 43, 59, 61, 65, 66, 69, each with a test that fails on the old generator (`tests/markdown.sh`, `tests/pattern/lookalt.hbnf`, `tests/css.sh`, `tests/ast.sh`, `tests/valued.sh`, `tests/backref/lookgroup.hbnf`, `tests/wire.sh`).  Not reproduced: 67; not a defect: 68.  50 is diagnosed in CONTEXTS.md (700 x 700 blocks), not fixed.  17 and 63 wait for the silent variants (Phase 2).

Queued reader and generator fixes (the titles are the item titles):

| item | what |
|---|---|
| 1, 2 | **done 2026-11-11 (`tests/lexer.sh`):** `'\'` is a backslash; `!'b'` and `&'c'` work.  `'c'` as a plain `"c"` everywhere was tried and not done: it changes markdown and Rust GraphQL (a letter in a rule of characters becomes a word), so `'c'` stays a code point elsewhere |
| 3 | **works (verified 2026-11-11, C and Rust; `tests/lexer.sh`)**: a lookahead over a sequence |
| 4, 5 | **done 2026-11-11 (C, Rust, Zig, Ada for `hidden`; C for the tape):** `hidden` over a rule that builds structure (read into a scratch value, no field in the tree; `tests/hidden.sh`); `!`/`&` over a rule that writes tape entries; `!closer(N)` with `%spaces N` works in both layouts; a rule that holds `eol` can be hidden |
| 6 | `%spaces N` at the start of a repeated group reads N as lost |
| 7 | a pattern rule's instances are named for the pattern |
| 11, 22, 29 | a negative lookahead over a rule that ends in one (does not reproduce); **22 and 29 done in all four backends 2026-11-11** (a lookahead rule, or a multi-character lookahead, in a rule of characters is scanned in C, Rust, Zig and Ada: the `Iter` atom was ported; `tests/scanlook.sh`) |
| 13, 14, 15 | **13 and 14 done 2026-11-11 (`tests/lexer.sh`)**: a `word` renamed `word-rule` is still the keyword boundary (C); a token exception with a literal operand; 15 (letters in a rule of characters) is how the notation reads, see CONTEXTS section 23 |
| 17, 63 | **done 2026-11-11 (C; `tests/layout.sh`)**: a lookahead over a rule that writes under `--layout=tape` runs it and puts the tape back (the grammar's `rollback`) |
| 23, 24 | **23 done 2026-11-11 (`tests/lexer.sh`)**: a hyperrule's literal argument follows `sensitivity string %i`; `$K` keeps the case property since a4f96d9 |
| 25 | `as K` and `$K` in the same sequence but in different group alternatives |
| 26 | **does not reproduce 2026-11-11** (a phrase rule named `text` compiles in Rust and Zig; `tests/lexer.sh`) |
| 27, 30, 31 | **27 (hyperrule half) done 2026-11-11 (`tests/lexer.sh`), 30 does not reproduce** (the root is the first rule the file you run defines, `%start` pins it); 31 is phase 2 of the switch (token and scalar overrides), designed and not built |
| 28, 61 | a generator crash; the generated tree dump (`--ast-tools`, `dump_<root>`) segfaults in its recursion |
| 60 | a rule that uses an up reference and also sets numbers with `%col` |
| 37, 38, 39 | **37 and 39 work (verified 2026-11-11, `tests/layout.sh`); 38 is by design** (alternatives that can both match are not scanned; the warning says so) |
| 9, 10, 12, 18, 19, 20, 32, 33 | the per-backend items (Ada, Rust, tree-sitter): **9 and 18 (Ada), 20 and 32 (Rust, a capture under `-D warnings`) done 2026-11-11 (`tests/lexer.sh`)**; 10, 12 and 19 do not reproduce; 33 is tree-sitter's lookahead.  Also found and fixed 2026-11-11: Rust type names of numbered groups collided (`select-clause-1-1` and `select-clause-11`: the COBOL parser did not compile in Rust and now agrees with C on every test file, `tests/cobol.sh`); a lookahead in a phrase rule did not skip white space first in Rust, Zig and Ada (a list did not stop at the word it names) |

**The pdp64 findings of the plan's Phase 1 (checked 2026-11-11 against the one-line reports; their repro grammars are not on this machine, ask the pdp64 side for them):** a character rule repeated directly in a value rule generates and parses here (a rule `num :: unsigned long = 1*digit %emit{ ... }`); an absent optional in a value rule compiles; the `%emit`-retry check does ignore a guard that tells two alternatives apart after their first byte (`"a" !"b" %emit{ } "c" | "a" "b" %emit{ }` is refused: the check looks at the first byte only, and a two-byte guard analysis is not built); the `--root` of bit-only reading and the enum-typed bit field were not tried.

Open decisions and unbuilt designs:

- [ ] The spellings `%label`, `%num`, `%action` and the rest (reserved words without `%`): open (CONTEXTS 10).
- [x] `col` (0-based) and `where (cond)` as a postfix: built 2026-11-11 (24), C backend.
- [ ] Facts (a rule's own attributes keyed by name): decided yes, nothing built (13).
- [ ] Labels (`name:` lines that set the context): open (16).
- [ ] Switch phase 2 (token and scalar overrides: decimal comma, per-region reserved words) and phase 3 (phrase variants in `ast`, the tape case): designed, not built (22).
- [ ] `=>` as the one arrow: consequence of a match (value, fact, grammar switch); decided 2026-11-02.  The surface was approved as shown on 2026-11-11 (CONTEXTS section 30); **built so far (C only): `set += tag`, `set -= tag`, facts `tag.attr = tag` and the reread `=> template [with ...]`** (`tests/consequence.sh`, by restarting the parse, mechanism a, R626), and `grammar(x)` phase 1.  The tree rewrite `->` (R624) is built too (C, the ast layout: `tests/consequence/tree.hbnf`).  Not built: hygiene, COBOL `COPY ... REPLACING`/`REPLACE`, restart at the calling rule, the chain of origins for errors (CONTEXTS section 30).  2026-11-10, 11: the rewrite form keeps a chain (the original span and the rule that fired) so an error names the text written and the rule, and the surface is chosen from five options shown first (R591, R596).
- [ ] Set-logic operators beside juxtaposition and `|` (intersection, element of, all of, and an unordered group): the author asked for an investigation 2026-11-11 (R601); five or six spellings with precedents are to be shown first.
- [ ] Bounded island `js.program in $R`.
- [ ] `hidden` directive, tagged union, a bench under 30 s per parser (memory: bench speed and hidden).
- [ ] Error recovery and restarts, with the Common Lisp restart system as the model (idea; not started).
- [ ] GLR: allowed by the scope note, pay only for what is used; not started.
- [ ] Granular check reporting: per-item results (backend / arch / grammar / suite), sequential, easy to run one item.
- [ ] Build files (every builder, not only make, cmake, cargo and autoconf: ninja and the rest too, the author 2026-11-11), `project.conf`, `builders/`, `languages/`, `hbnfversion`, helper code in `.c`/`.rs` files and `.o` files linked in, several grammars named by one project: decided in outline 2026-10-29 and 30 (decision register R608-R618, R619), nothing built (the plan of 2026-11-11, Phase 7).
- [ ] The conf glue out of the templates into an included C header.
- [ ] **Port the C-only features to Rust, Zig, Ada, tree-sitter** (`where (col ...)` and the `Iter` atom, a rule of characters that repeats a rule or group holding a lookahead or a position test, are ported 2026-11-11: fixed-format COBOL agrees with C on every test file in Rust, Zig and Ada; the standing rule is C first, then the rest): `as K`/`$K`, up references, `^.rule`, `bol`/`eol`, the scanned lookahead, overlay, unwind marks, the arena, the tape captures, the SSE2 loop, the context-set hash.

Prio:
Note:

## 4. Corpora (grammars)

- [ ] **COBOL** (free format, and fixed format since 2026-11-11): 3 gaps in the scan suite against cobc, 0 in NIST (`tests/cobol/scan-baseline.txt` = 3: `>>IF`/`>>ELSE` directives that choose text, the LIST-BOX screen extension, 2023's `VARYING ... INVALID WHEN`; `nist-baseline.txt` = 0; a comma may be the decimal point); fixed format: `corpus/cobol/cobol-fixed.hbnf`, `tests/cobol/fixed-baseline.txt` = 2 (`ACCEPT ... MESSAGE COUNT`, a data item named PROCEDURE), not yet `>>SOURCE FORMAT` switching, a word continued with `-`, text in the indicator column; copybooks, the embedded languages (SQL, CICS, DLI, JCL), PICTURE as its own grammar.  RFCPLAN step 20 (ALGOL 68, C++, COBOL on the list; IMP72 cancelled).
- [ ] **HTML**: the places where the grammar and html5lib differ (`corpus/html/tests/oracle-stricter/`: documents html5lib refuses and the grammar accepts); JS and CSS as islands (CONTEXTS 27); the island 26/27, 30, 31 items above.
- [ ] **JavaScript** (ECMAScript 2023, Script and Module) and **CSS** (Syntax 3, Selectors 4): known gaps against V8 / tinycss2 (see their READMEs).
- [ ] **SGML** and **GraphQL**: no oracle.
- [ ] **Markdown to Typst** (`corpus/markdown`): a subset of CommonMark with tables; the `%spaces` bug (26/6).
- [ ] ALGOL 68, C++ grammars: not started; targets since 2026-11-11 (the user): the order is COBOL (full front end, old and modern dialects), the C preprocessor, ALGOL 68, then C++ one standard at a time, oldest first, the preprocessor included; about 5,000 lines of grammar and epilogue for each grammar, a soft limit (RFCPLAN step 20; decision register R594-R602).
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
- [ ] The out-of-tree build directory is 21 GB of dev generators (`bin/hbnf-*`) and scratch (`xw`, `xcb*`, `x2`, `rel`), and the agent worktrees take 594 MB (the paused speed agent's among them); clean both.
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
