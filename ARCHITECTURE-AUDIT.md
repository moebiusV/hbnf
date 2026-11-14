# Architecture audit, 2026-11-14: what the author decided, what the documents said, what is built

Taken at `origin/main` 01e9b2f.  Line numbers below are of that commit and move as the files change.  Purpose: no more confusion from
documents and code comments that say something other than what the author decided or what the code does.  Decisions are the author's
own words only (`decision-register.md`); where this file reports what an assistant wrote, it says so.

Status vocabulary (the author's rule): a decision stays a decision when its details are open, and is marked **details tbd**.
"Proposed" is for an assistant's suggestion the author has not accepted; "open" is for a question he has not answered.

## Part 1. What the author decided

### The generator pipeline (2026-11-14; R583, R608, R703, R704, R708 to R724)

1. **Front end.**  The grammar is read, checked and optimised into the IR: "the 40 operations" (called hbnf-ir or hbnf-ops in an earlier draft of `LANGUAGES.md`).  R708.
2. **Layout transformer.**  The grammars under `layouts/` are rewrite grammars that transform the IR into its output form.  R709.
3. **Language transformer.**  A `languages/` directory holds a rewrite grammar per target language; ONE emitter back end chooses it
   (today it chooses a set of Mustache templates; afterwards the grammar) and it rewrites the layout-shaped IR into source text.
   This replaces the Mustache templates and the per-language Ada emitters.  The templates themselves do the rewrites; they are written
   externally and used like an interpretive language.  R710, R583, R608.
4. **The mechanism is `->`, `=>`, `=>>`**, the rules that already do COBOL COPY/REPLACE and the C preprocessor.  `%emit` is not
   deprecated or forbidden; it was not the main mechanism envisioned for this, and stays for smaller things.  R711, R693.
5. **Compiled or interpreted:** the layout and language grammars may be compiled to `.o` files and linked in; they need not run
   interpreted.  R712, R703, R704.

6. **All the stages are hbnf grammars with epilogues, linked in as `.o` files**: (a) parse the grammars and emit the optimised IR,
   (b) the layout grammars transform it into the layout form, (c) the language grammar takes the layout's output, "possibly a different
   ir format, possibly not", and transforms it from the 40 operations into code.  R714.
7. **The build system chosen is applied after the language stage.**  The build system was already decided (R610 to R618, R634:
   `build` directive and `project.conf`; standalone, make, cmake, cargo, autoconf, ninja and the rest, a grammar each in `builders/`),
   but no document connected it to the pipeline.  R715.  Whether a builder reads the same IR is the author's "possibly" (R716).
8. **The builder is "a compile plus packaging concern"**: languages that emit no `.o` files (python, node) still need their emitted
   files wired together to run and to be packaged, and the builder must know how.  R718.  It generates the makefiles, configure files
   and infrastructure for building the emitted code and `.o` files into a project, and a command that packages the project up, for
   sharing and inspection; it need not compile anything itself.  R719.  It emits that infrastructure without running it, as hbnf
   emits parser code without running it, and each builder is its own grammar with an epilogue.  R720.
   Layouts, languages and builders are one kind of thing: grammars and epilogues that hbnf uses as part of itself while running,
   compiled to `.o` files that are linked in; several languages could therefore interoperate in hbnf, possible but not a goal now.  R721.
   The Ada reader will also become an hbnf grammar plus an epilogue, possibly a minimal one that links in the existing Ada analysis
   and optimisation code.  R722.  There can be several readers, one for each BNF variant hbnf supports: "ebnf, abnf, ybnf, hbnf etc" (R724; "ybnf is the yacc dialect").
   R723, R724.  Today these are dialects of the one Ada reader (`dialect` directive, `--dialect=bnf|ebnf|abnf|ybnf|hbnf`,
   `Set_Dialect` and the `dialect` line in `hbnf_grammar.adb`), so this moves the choice from a flag to one reader grammar per variant.
9. **"Jets" is fine, "it is a term of art"** (R713): the removal of the word in R352 is withdrawn.

Details tbd: what wiring and packaging each language needs and the form of the packaging command (R718, R719), whether the layout's output is a different IR format or the same one, how the `.o` files are built and linked, the exact list of operations, whether layouts nest under `languages/` (R614),
the loading interface.  The callback interface in `LANGUAGES.md` (`hb_lang_*`, `dlopen`) is the implementer's proposal, not a decision.

### Language targets and notation (2026-11-11; R594 to R602)

- A complete C++23 front end including the preprocessor: R594, R595, R598 ("Annex A disambiguation" is the assistant's wording, not in those rows).
- The grammar reads like the printed standard: `opt`, `X-seq`, `X-list`, "one of" lists, nesting-aware angle brackets.  Approved,
  R594; details tbd.  Only `one of` is built.
- The preprocessor as rewrites: the author guessed "that the rewrite rules will make the pre processor fairly straightforward"
  (R595); R597 asks what COBOL COPY REPLACING could teach, and the lesson (substitutions local, explicit, fed back to the grammar) is
  the assistant's answer, not a decision.
- Set-logic operators, with sequence and "sequence does not matter" both expressible (R601, R604 to R607, R643 to R689).
- 5,000 lines is a **soft** limit, **per grammar**, not a total (R600).
- A separate front end per C++ version (R599); ALGOL 68 (R598); COBOL, full coverage of old and modern dialects (R602).
- All four backends alike: "bring ada backend up to par before anything else" (R698); "all jet syntax must work for all supported languages" (R702).

What the author did not say, though documents attribute it to him: "oldest first" for C++ versions; a "hard ceiling"; "shared
infrastructure is outside the count" (the assistant's wording); a priority order of six steps (the assistant's handoff text listed one;
the author has not restated it; details tbd).

## Part 2. Wanted, documented, built

| Point | What the documents said at 01e9b2f | What the code does |
|---|---|---|
| Build step | Documented in R610 to R618, R634, the Build files item of `TODO.md` and `decisions-and-status.md` (Build files), apart from the pipeline; `LANGUAGES.md` named `builders/` once. | Not built: no `builders/`, no `project.conf`, no `build` or `hbnfversion` directive in `hbnf_grammar.adb`. |
| Three-stage pipeline | Stated nowhere as a pipeline.  `LANGUAGES.md` had stages 1 and 3, no layout stage, "Draft … Nothing here is built" over a section headed "Decided (R703)". | Not built.  `hbnf.adb:657-703` picks one of five text emitters by a string if-chain (tree-sitter, c, rust, zig, ada) and `hbnf.adb:430-560` one of four wire emitters: nine hand-written emitters. |
| IR of about forty operations | A prose list, `LANGUAGES.md:50-54`.  R3 and `decisions-and-status.md:1769` said "the ast is the ir … no separate IR stage" (DONE). | No such type.  Nearest: `Block_Op`, 27 source-construct members, `hbnf_grammar.ads:178-205`. |
| Layouts are rewrite grammars over the IR | Not said.  `RFCPLAN.md:2645` "a layout … inserts the `%emit` blocks"; `ABNF.md:342` raw C with `@holes@`. | `ast` and `tape` are Ada (`Tape_Layout`, `hbnf_grammar.adb:15327-15772`).  `tailq`, `rb` are C macro tables read by the C backend only; neither file has a rewrite rule. |
| Languages replace Mustache and the emitters | R583, R608 said so.  `RFCPLAN.md` 13b said `%emit` naming templates, "The shape is decided", labelled "Open"; README, `USENIXSUBMISSION.md:556-564`, `HISTORY.md:681`, commit 1133cf1 presented Mustache templates as the design. | 71 templates (45 C, 9 Rust, 8 Zig, 9 Ada) carry prologues, type declarations and fixed runtime text.  Per-rule logic is Ada string-building: about 2,240 `Append` calls in `hbnf_c.adb` (13,122 lines); Ada 7,149, Zig 6,224, Rust 5,446 lines. |
| Rewrites applied to the generator's own IR | Described only for generated parsers (`CONTEXTS.md` sections 25 and 30). | No code path.  No rewrite or grammar interpreter inside the generator. |
| `=>`, `=>>`, `->` | `=>>` defined only in R693; `CONTEXTS.md:1283` said it was replaced; headings said "for the author to approve; nothing built". | Built in all four backends.  C continues reading in place; Rust, Zig, Ada restart the parse.  `hidden`, `hiding` and template functions are C only. |
| Set logic | `decisions-and-status.md:795` IN THE AIR; `CONTEXTS.md` "nothing built"; absent from `ABNF.md`. | Built in all four (`one of`, `all of`, `some of`, `any of`, `choose`, `permute`, `intersect`, `in`/`not in`); `choose … with replacement` C only. |
| Annex A `opt`, `X-seq`, `X-list` | Approved in R594, filed "to be shown", `CONTEXTS.md:1050`. | Not built; only `one of`. |
| Preprocessor as rewrites | `decisions-and-status.md:560` "not started"; `RFCPLAN.md:2777` "an idea, not decided"; README "Next". | `corpus/c/cpp.hbnf`, 1,407 lines at 01e9b2f, about 1,190 of them native C; C backend only. |
| COBOL | `TODO.md`, `decisions-and-status.md`, `corpus/README.md` stale; `corpus/cobol/README.md` contradicted itself four times. | 792 lines in five files; baselines 2 / 0 / 1; fixed format in all four backends; COPY/REPLACE C only; no OO, no `>>IF`. |
| Soft limit per grammar | Right everywhere. | Not measured.  Nothing says whether generated tables or native C count. |
| Priority order | Repository: COBOL, preprocessor, ALGOL 68, C++ "oldest first".  "The plan of 2026-11-11, Phases 1–7" cited in five places; it is not in the repository. | Engine work, COBOL fixed format and COPY, then the preprocessor. |
| Front end and readers (R722 to R724) | `METACOMPILERS.md:88` listed self-hosting as "not yet"; `RFCPLAN.md` step 13a plans a grammar for the notation (`hbnf.hbnf`) with no pointer to R722; the ledger entry "Grammar for HBNF itself" is TO DO. | No `hbnf.hbnf`.  The reader is Ada (`hbnf_grammar.adb`); BNF, EBNF, ABNF, YBNF and HyperBNF are dialects of that one reader, chosen by the `dialect` line or `--dialect=`. |
| Four backends as equals | Not stated as a requirement; many stale "C only" statements. | See the rewrite row for what the other three still refuse. |

Also found: eleven rows in the register ended "open" (ten decisions and one finding); the word "jets" was removed by R352 and used again in R701 and R702 (settled by R713: it stays); the word
"layout" has three meanings (the output data structure, the shape of generated code, the pretty-printer hook type);
`hbnf_schema.hbnf` is the obconf configuration grammar, not a schema of the notation; the documents carried local-machine inventories.

## Part 3. Corrections made on this branch (documents and comment text only)

The groups are separate commits, except that `LANGUAGES.md` and `decision-register.md` share one; later commits record R713 onward.

- **`LANGUAGES.md`**: the one authoritative statement; later the build step (R715) and the "all stages are hbnf grammars" statement
  (R714) were added.  Status "Decided; not built; details tbd"; the three stages in order; one
  emitter back end; `%emit` stays for smaller things; the `hb_lang_*` interface, `dlopen` and the static-versus-dynamic note marked as
  the implementer's proposal; measurements refreshed.
- **`decision-register.md`**: R708 to R712 appended with the author's words; forward pointers on R3, R153, R512, R623, R624; the ten
  rows ending "open" re-labelled by what later rows show (R674 was a finding, now "fixed by R676").
- **`RFCPLAN.md`**: 13b marked superseded in part, old text kept as history; forward pointers on `%emit`-as-backend passages; the
  "no longer Ada … 65 templates" claim corrected; layout, interpreter, preprocessor and "not decided" labels reconciled.
- **`CONTEXTS.md`**: status table and the headings of sections 25, 29, 30 brought to what is built; "As settled" summaries at the top
  of sections 29 and 30 so the append-only log below cannot be read as current.  Section numbers unchanged (code comments cite them).
- **`decisions-and-status.md`**: new subject "Generator pipeline: operations, layouts, languages"; the IN THE AIR entries that were
  decided moved to TO DO or DONE; counts recomputed; local-machine inventories removed.
- **Other documents** (README, `TODO.md`, `ABNF.md`, `TUTORIAL.md`, `WHY.md`, `METACOMPILERS.md`, `COMPILER-COMPILER.md`,
  `USENIXSUBMISSION.md`, `HISTORY.md` (a dated forward note only), `grammars/README.md`, `corpus/README.md`, `corpus/c/README.md`,
  `corpus/cobol/README.md`): what is true today stated; Mustache and four-emitter descriptions say they are decided to be replaced;
  `ABNF.md` gained rows for `=> template`, `=>>`, facts, `hiding`, set logic; stale "C only" cells fixed.
- **Code comments** in 20 files (`hbnf_grammar.ad[sb]`, `hbnf_compilable.ad[sb]`, `hbnf_c.adb`, `hbnf.adb`, `hbnf_wire*.ads`,
  `hbnf_template.ads`, `hbnf_shape.ads`, `libhbnf.gpr`, tests, `cpp.hbnf`, `cobol.hbnf`): "C only so far / not built yet" statements the
  code contradicts, misdescriptions, the retired `list-head` spelling, a citation of a nonexistent CONTEXTS section 31.  No code line
  changed.  The `cpp.hbnf` header now says about 1,190 of roughly 1,400 lines are native C.

## Part 4. Left for the implementer and the author

Code, not comments (not changed here):

- `hbnf.adb:283`: `--layouts=DIR` can never match (an 11-character slice is compared with a 10-character string); only
  `$HBNF_LAYOUTS` and the default work.
- `tests/lexer/look-ws.hbnf:4` includes an absolute path under a local home directory; `corpus/c/cpp-gnu.hbnf:418` has local build
  paths in its generated table (origin: `scripts/build-gcc.sh`).
- Error and warning strings that still say "only the C backend generates" or "can be emitted in C so far":
  `hbnf_compilable.adb` near lines 1393, 1397, 1461 and 1464, and `hbnf.adb` near lines 365, 375, 519 and 549; the operation list in the error near line 13220 of `hbnf_grammar.adb`
  omits `key` and `generate`.
- `tests/consequence.sh`: the MODE `r` branch is used by no call (its header, the `run()` comment and the comment near line 105 were corrected).
- Four templates are referenced by no Ada source: `c_alt_atend`, `c_alt_reset`, `c_seq_kind`, `c_seq_literal`.
- `Class_Kind` is declared five times (`hbnf_c.adb` twice, Rust, Zig, Ada) although `hbnf_shape.ads` is meant to hold what the
  emitters share.

Questions only the author can answer, each decided neither way here:

1. Do the generated tables in `cpp-gnu.hbnf` and the native C inside `cpp.hbnf` count toward the 5,000-line soft limit per grammar?
2. The order of work after the preprocessor (the repository says COBOL, preprocessor, ALGOL 68, C++; the 2026-11-11 handoff text listed
   six steps; the "plan of 2026-11-11, Phases 1–7" cited in five places is not in the repository).
3. Do layouts nest under `languages/` (R614, "Maybe")?
4. Should `ast` and `tape` become files under `layouts/` like `tailq` and `rb`, as the pipeline implies?
5. Does a builder read the same IR as the layout and language stages (R716, "possibly")?
6. Is the output of the layout stage a different IR format, or the same one (R714, "possibly a different ir format, possibly not")?

Answered since the first version of this file: "jets" (R713, it stays as a term of art); the front end (R722, the Ada reader also becomes
an hbnf grammar plus an epilogue, possibly a minimal one that links in the existing Ada analysis and optimisation code).

Details tbd within decided matter: the operation list and the typing of each operation; how a layout grammar names the shape it
produces; how a language grammar receives it; building and linking the `.o` files; how the one emitter back end finds the grammar.

Not re-verified in this pass: about 80 section and step citations in code comments (two were checked); the bounds claim in
`hbnf_compilable.ads:7-15`; whether the conforming XML grammar generates in Rust, Zig and Ada; whether silent variants are still
unbuilt.  The Ada sources compile with these edits (checked into a separate build tree); the link step was not run on the machine used.
