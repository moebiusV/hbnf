# What is left to implement or fix (written 2026-11-05, corrected 2026-11-14)

Written at the pause; to be annotated for direction and priorities.  Each item has a `Prio:` and a `Note:` line to fill in.
Sources: CONTEXTS.md (status table and section 26, the reader and generator findings by number), RFCPLAN.md, the memory notes,
the agents' hand-backs of 2026-11-04.  Where an item is a number like "26/34" it is the item of CONTEXTS.md section 26.

State at the pause (2026-11-05): `main` was pushed through 4bb4e9a, and the static `./hbnf` was built from the sources of 9884a84.
The speed work is paused.

Corrected 2026-11-14: what was listed here as not built and has been built since (the `=>`, `=>>` and `->` rewrites, facts, the
set-logic operators, fixed-format COBOL, COBOL `COPY`/`REPLACE`, the C preprocessor grammar) is marked as built below, and the
generator pipeline decided on 2026-11-14 (front end, operations, layout transformer, language transformer; R708 to R724 (the front end and the readers become grammars too, R722 to R724; the builders, R715 and R718 to R721)) is
item 1 of section 3.  Where a line below says "C only", `ABNF.md` has the current backend support; the two disagree where this
file was not rewritten.

---

## 1. Benchmarks: all rerun on 2026-11-05, on a busy machine

Everything below was rerun at hbnf 9884a84 on a machine that was "as quiet as it will get", which is not quiet: the YAML probe read 18-19 ms
(quiet is 8.4-9.6) and the load average was 9 (another job on cores 0-4, and a VM).  The reference rows were compared in each footnote; no figure was adjusted.
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
| a long-running job on cores 0-4 | makes the machine unusable for timing (even on idle cores: memory bandwidth) | agree a window when it is paused |

Prio:
Note:

## 2. XML

- [ ] **`tests/xml-diff.sh` fails where the oracle is expat 2.7.1, with the shipped `./hbnf` and with a pristine build of the same sources** (found 2026-11-11, not caused by Phase 1): expat 2.7.1 accepts four bad XML declarations that hbnf refuses (`corpus/xml/tests/bad/xml-decl-version-{empty,letters,major,no-minor}.xml`, reported as `oracle accepts bad`), and expat accepts some of the random mutations hbnf refuses.  The case set was made against another expat; decide whether the oracle check should name the expat version it was made with, or skip a case the oracle's version does not refuse.
- [ ] **The other backends cannot generate the conforming XML grammar.**  Rust and Zig emit `compile_error!` (the recursion walk is C-only code), Ada did not generate it (it had no contexts then; contexts and facts were added to Ada on 2026-11-13, and whether the XML grammar now generates in Rust, Zig and Ada has not been rechecked), tree-sitter refused it before.  Way back: a value kept with a name in a context (CONTEXTS 13) instead of code, so the check is grammar and not C.  (26/41)
- [ ] **Not checked yet, all need an entity's replacement text parsed as content when it is used** (a bounded island, CONTEXTS 27, or a stored value): the balance of markup in an entity (`<!ENTITY e "<b>">`), a `<` or an unparsed entity inside an entity's text, `&#38;#0;`, the external subset and conditional sections, namespace constraints beyond the lexical rule.  They are in `corpus/xml/tests/loose` and the README's "Not checked".
- [ ] **Speed, from the profile (64 M instructions per 2 MB parse):**
  - the failing trial at the end of each list loop: 8.6% of instructions, the biggest.  Needs the lookahead analysis to know that a leading `!( literals )` removes first bytes (`HBNF_Lookahead.Branch_First`), then a precheck at the dispatch.  **Half done in the paused speed work** (it compiled; not measured).
  - variable-size choice nodes (48 bytes where a text item needs 24; about -1.8 MB of 9.7 MB, and removes the alloc/unwind/memset around a failed alternative)
  - the name DFA fast path (`scan_qname`, 72 instructions per call, 4%)
  - fusing `&legal` into the scans (4.6%)
  - list links in arrays (memory only: -25% JSON/TOML, -19% XML)
  - automatic left-factoring through captures (26/48): the element was factored by hand and saved a millisecond; the natural spelling would pay it
  - hidden dependence of the arena patch on `MADV_POPULATE_WRITE` (Linux 5.14+); older kernels fault as before
- [x] **Latent hazard** in the context-set hash cache (`hbnf_lh_s`, 9884a84): fixed 2026-11-11 by dropping the cache (the hash reads at most eight bytes and the length, so what it saved was a few multiplies); `tests/context/ctxhash.hbnf` asks about a buffer, overwrites it and adds, and fails on the old template.
- [ ] **Silent variants (CONTEXTS 26/64), and the rewrite rules, which are built since 2026-11-11 (section 3):** bench them on the XML grammar, for the readable grammar and for speed ("readable AND fast, no stone unturned").  The profile says nothing in the XML parse is output a grammar would drop, so the speed guess is "no gain"; it is a guess.
- [ ] The README claim: "fastest conforming XML parser" only after a quiet run shows it for the tree (the tape already is).

Prio:
Note:

## 3. The language and the generator (CONTEXTS section 26, by number)

**Done 2026-11-11 (Phase 1 of the plan of 2026-11-11, which is not in the repository):** 6, 21 (the UTF-8 half: `tests/utf8.sh`; the NUL needs a `parse_text_n`, to be settled), 28, 43, 59, 61, 65, 66, 69, each with a test that fails on the old generator (`tests/markdown.sh`, `tests/pattern/lookalt.hbnf`, `tests/css.sh`, `tests/ast.sh`, `tests/valued.sh`, `tests/backref/lookgroup.hbnf`, `tests/wire.sh`).  Not reproduced: 67; not a defect: 68.  50 is diagnosed in CONTEXTS.md (700 x 700 blocks), not fixed.  17 and 63 wait for the silent variants (Phase 2).

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

**The pdp64 findings of the plan's Phase 1 (checked 2026-11-11 against the one-line reports; their repro grammars are not in this repository, ask the pdp64 side for them):** a character rule repeated directly in a value rule generates and parses here (a rule `num :: unsigned long = 1*digit %emit{ ... }`); an absent optional in a value rule compiles; the `%emit`-retry check does ignore a guard that tells two alternatives apart after their first byte (`"a" !"b" %emit{ } "c" | "a" "b" %emit{ }` is refused: the check looks at the first byte only, and a two-byte guard analysis is not built); the `--root` of bit-only reading and the enum-typed bit field were not tried.

Unbuilt designs and open questions (a decision whose details are not worked out is a decision, marked "details tbd"):

- [ ] **The generator pipeline, decided 2026-11-14 (R708 to R724 (the front end and the readers become grammars too, R722 to R724; the builders, R715 and R718 to R721); `LANGUAGES.md`), not built, details tbd:** the front end reads, checks and optimises the grammar into the intermediate representation (about 40 operations); the layout transformer, a rewrite grammar under `layouts/`, turns it into the layout's form; the language transformer, a rewrite grammar under `languages/` chosen by one emitter back end, turns that into source text with `->`, `=>` and `=>>`.  This replaces the Mustache templates and the per-language Ada emitters.  `%emit` stays for the smaller things; it is not the main mechanism here.  The grammars may be compiled to `.o` files and linked in, or run interpreted.  Details tbd: the exact list of operations, the loading interface (the C callbacks and `dlopen` of `LANGUAGES.md` are the implementer's proposal), and whether layouts nest under languages.

- [ ] The spellings `%label`, `%num`, `%action` and the rest (reserved words without `%`): open (CONTEXTS 10).
- [x] `col` (0-based) and `where (cond)` as a postfix: built 2026-11-11 (24), in C, and ported to Rust, Zig and Ada the same day (fixed-format COBOL agrees with C on every test file in all four).
- [x] Facts (a rule's own attributes keyed by name): decided yes (13); built in C 2026-11-11 and generated in Rust, Zig and Ada since 2026-11-13 (R698).
- [ ] Labels (`name:` lines that set the context): open (16).
- [ ] Switch phase 2 (token and scalar overrides: decimal comma, per-region reserved words) and phase 3 (phrase variants in `ast`, the tape case): designed, not built (22).
- [x] `=>` as the one arrow: consequence of a match (value, fact, grammar switch); decided 2026-11-02, the surface approved 2026-11-11 (CONTEXTS section 30), built.  `set += tag`, `set -= tag`, facts `tag.attr = tag`, `grammar(x)` and the rewrites are in `tests/consequence.sh`; `->` is the tree rewrite (R624, the ast layout), `=> template` replaces the matched text and goes on reading at the start of the new text, and `=>>` replaces it and reads everything again from the start (R693).  In C the `=>` continues in the live parse; in Rust, Zig and Ada it restarts the parse (R698).  C only: `hidden`/`hiding` and a template function in a rewrite, `->` with a fact or a function or with `layout tape`, COBOL `COPY ... REPLACING`/`REPLACE` (`cobol-copy.hbnf`) and the C preprocessor (`cpp.hbnf`).  Built too: the chain of origins for errors in C (R665).  Not built: hygiene (fresh names).  The rewrite form was chosen from five options shown first (R591, R596, R624, R626, R693).
- [x] Set-logic operators beside juxtaposition and `|`: the author asked for an investigation 2026-11-11 (R601) and chose the spellings 2026-11-12 (R643 to R672); built in all four backends: `x in S` / `not in`, `one of ( ... )`, `a intersect b`, `all of`, `some of`, `any of`, `( ... ) choose k`, `permute k`; `choose ... with replacement` is C only.  `unique` is not built.
- [ ] Bounded island `js.program in $R`.
- [ ] `hidden` directive, tagged union, a bench under 30 s per parser (memory: bench speed and hidden).
- [ ] Error recovery and restarts, with the Common Lisp restart system as the model (idea; not started).
- [ ] GLR: allowed by the scope note, pay only for what is used; not started.
- [ ] Granular check reporting: per-item results (backend / arch / grammar / suite), sequential, easy to run one item.
- [ ] Build files (every builder, not only make, cmake, cargo and autoconf: ninja and the rest too, the author 2026-11-11), `project.conf`, `builders/`, `languages/`, `hbnfversion`, helper code in `.c`/`.rs` files and `.o` files linked in, several grammars named by one project: decided in outline 2026-10-29 and 30 (decision register R608-R618, R619, R715, R718 to R721), nothing built (the plan of 2026-11-11, Phase 7; that plan is not in the repository).  `languages/` is the generator pipeline item above and `LANGUAGES.md`.
- [ ] The conf glue out of the templates into an included C header (the templates themselves are decided to be replaced, `LANGUAGES.md`).
- [ ] **Port the C-only features to Rust, Zig, Ada, tree-sitter.**  Ported 2026-11-11 to 13: `where (col ...)` and the `Iter` atom, a rule of characters that repeats a rule or group holding a lookahead or a position test, contexts, facts, the `=>`/`=>>`/`->` rewrites, the set-logic operators, `%emit`/`%where`/`%bind`/`%action` (R686 to R702).  The list that was here before them, to be rechecked against `ABNF.md` before working from it: `as K`/`$K`, up references, `^.rule`, `bol`/`eol`, the scanned lookahead, overlay, unwind marks, the arena, the tape captures, the SSE2 loop, the context-set hash.  Still C only, as far as the sources show: `hidden`/`hiding` and a template function in a rewrite, `choose ... with replacement`, `->` with a fact, a function or `layout tape`, the `layout_ops` containers (`tailq`, `rb`), the keyword table, `--forks`, `cobol-copy.hbnf` and `cpp.hbnf`.  The rule for a new feature, until the language directories exist: in C first, in the others when asked (`LANGUAGES.md`).

Prio:
Note:

## 4. Corpora (grammars)

- [ ] **COBOL** (free format, and fixed format since 2026-11-11, and `COPY`/`REPLACE` as rewrites since 2026-11-13, C only): 2 gaps in the scan suite against cobc, 0 in NIST (`tests/cobol/scan-baseline.txt` = 2: `>>IF`/`>>ELSE` directives that choose text, the GUI screen extensions; `nist-baseline.txt` = 0; a comma may be the decimal point); fixed format: `corpus/cobol/cobol-fixed.hbnf`, `tests/cobol/fixed-baseline.txt` = 1 (`NC205A`, a word continued with `-` across lines), not yet `>>SOURCE FORMAT` switching, text in the indicator column; `COPY` between any two tokens and in fixed format; object-oriented COBOL; the embedded languages (SQL, CICS, DLI, JCL), PICTURE as its own grammar.  RFCPLAN step 20 (ALGOL 68, C++, COBOL on the list; IMP72 cancelled).
- [ ] **HTML**: the places where the grammar and html5lib differ (`corpus/html/tests/oracle-stricter/`: documents html5lib refuses and the grammar accepts); JS and CSS as islands (CONTEXTS 27); the island 26/27, 30, 31 items above.
- [ ] **JavaScript** (ECMAScript 2023, Script and Module) and **CSS** (Syntax 3, Selectors 4): known gaps against V8 / tinycss2 (see their READMEs).
- [ ] **SGML** and **GraphQL**: no oracle.
- [ ] **Markdown to Typst** (`corpus/markdown`): a subset of CommonMark with tables; the `%spaces` bug (26/6).
- [ ] ALGOL 68, C++ grammars: not started; targets since 2026-11-11 (the user); the order recorded here is the implementer's, not the author's: COBOL (full front end, old and modern dialects), the C preprocessor (built since, C only: `corpus/c/cpp.hbnf`), ALGOL 68, then C++ one standard at a time, the preprocessor included (the words "oldest first" that stood here are the implementer's, not the author's; the order of the C++ versions is details tbd); about 5,000 lines of grammar and epilogue for each grammar, a soft limit (RFCPLAN step 20; decision register R594-R602).
- [ ] The C compiler: action/emit into LLVM ORC and liblld, as in the IMP72 project, then c79 to facetlang: not started.

Prio:
Note:

## 5. Documents

- [ ] `HISTORY.draft.md`, `RESUME-9b.md`, `RESUME-9c.md` (untracked): fold into HISTORY.md or delete.
- [ ] `HyperBNF as leverage for LLMs` (the stated purpose): keep it written where it is and do not over-claim (memory note).
- [ ] After the quiet rerun: README, WHY.md, HISTORY.md benchmark blocks are generated by `sh bench/update-docs.sh`; the hand-written prose around the XML table (README "JSON, TOML, YAML and XML against the parsers people use") should be re-read against the new numbers.
- [ ] CONTEXTS.md: keep the status table up to date with each decision; its status table was brought up to date on 2026-11-14 for R594 to R712; keep it current with each later decision (R713 onward).

Prio:
Note:

## 6. Housekeeping

- [ ] Keep core files, `hbnf-*.tar.gz` archives, scratch notes and `__pycache__` directories out of the repository root: ignore them in `.gitignore` or delete them.
- [ ] Run the suites where the results directory is writable by the user who runs them (a container run can leave `tests/results/` owned by another user).

Prio:
Note:

## 7. Questions for the author

1. Is "fastest conforming XML parser" the headline, or the tape / typed-tree pair stated separately?
2. Should the benchmark run with transparent huge pages off as well as on?
3. May the long-running background job be paused for one 30-minute window (the whole of `libs.sh`)?
4. Silent variants and rewrite rules: before or after the failing-trial work?
5. Which of the other backends is to be brought back to the XML grammar first: Rust, Zig or Ada?
