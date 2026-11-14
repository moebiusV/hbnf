# The generator pipeline: operations, layouts, languages

Status: **Decided** (R583, R608, R703, R704, R708 to R712 of `decision-register.md`); **not built**; **details tbd**.  The author's
words of 2026-11-14 are the authority where this file and any other document differ: "The pipeline will go from the front end that
creates the 40 operations passes it to the layout transformer rewriter, and then it will be passed to the backend language.  Rewrite
transformer" (R708); "the languages/ hbnf dir would have grammar together with epilogue that has all the native code needed to compile
standalone .o file, then the ada could just link in the .o using a standard interface, which would make supporting another language
just a matter of dropping another language into the languages/ dir" (R703); "the original goal for hbnf is to support a bunch of
languages besides the current 4" (R703).  What is decided is the shape below; what is marked **details tbd** or **the implementer's
proposal** is not a decision.

## The pipeline: three stages and the build step (R708, R714, R715)

All the stages are written as **hbnf grammars with epilogues, linked in as `.o` files** (R714): "so it is a pipeline, hbnf grammars plus
epilogues and linked in .o files will a) parse the grammars and emit optimized ir b) layout grammars take the ir and transform it into
the layout form c) takes the output of layout, possibly a different ir format, possibly not, and transforms it from the 40 operations
into actual code".  Stage (a) as hbnf grammars is a question for the author (R717): the reader is Ada today.

1. **Front end.**  The reader, the analyses (compilability, lookahead, contexts, facts) and the optimisations turn the grammar into
   the IR: about forty typed operations (hbnf-ir, hbnf-ops; the list is *details tbd*, a first count is under "The operations" below).
2. **Layout transformer** (R709).  The grammars under `layouts/` are **rewrite grammars over the IR**: each one decides the output form
   of the parser (tree, tape, tailq, rb and the like) by rewriting the IR into the shape that form needs.
3. **Language transformer** (R710).  The grammars under `languages/` are **rewrite grammars**, one per target language.  ONE emitter
   back end chooses the grammar for the language (today it chooses a set of Mustache templates; afterwards the grammar), and that
   grammar rewrites the layout-shaped IR into source text.  This replaces the Mustache templates and the four per-language Ada
   emitters.  "The templates themselves do the rewrites; the templates will be written externally and then used like an interpretive
   language."

4. **Builder** (R715; R610 to R618, R634).  The build system chosen by the `build` directive or by `project.conf` (standalone, make,
   cmake, cargo, autoconf, ninja and the rest, each a grammar in `builders/`) is applied after the language stage.  Whether a builder
   reads the same IR as the layout and language stages is a question for the author (R716: "possibly it gets access to the same ir");
   hbnf choosing which code goes in which files (R610) means a builder needs at least the list of emitted files.  Nothing of this is
   built (`builders/`, `project.conf`, the `build` directive do not exist).  The builder is "a compile plus packaging concern" (R718):
   a language that emits no `.o` files (python, node) still needs its emitted files wired together so that they run properly and can be
   packaged properly, and the builder has to know how; for a compiled language it also compiles and links.  Details tbd: what wiring and
   packaging each language needs, and whether that knowledge lives in `builders/` or in the language directory (R614).

Whether the output of the layout is a different IR format or the same one is *details tbd* (R714: "possibly a different ir format,
possibly not").

The mechanism of stages 2 and 3 is the rewrite rules `->` (the tree rewrite), `=>` (replace the matched text and go on reading at the
start of the new text) and `=>>` (replace it and read everything again from the start): the rules that already do COBOL COPY and
REPLACE and the C preprocessor (R693).  `%emit` is not that mechanism: it stays in the notation and in all four backends, for the
smaller things it was made for, and the main mechanism is `->`, `=>`, `=>>` (R711).

The layout and language grammars may be **compiled to `.o` files and linked in**; they need not run interpreted.  A parse is like an
interpreter of its input, and the rewrite rules run the same way (R712).  *Details tbd:* how the `.o` files are built and linked, and
whether layouts nest under languages (R614).

## Where it stands today (measured, 2026-11-14)

| part | today | size |
|---|---|---|
| the grammar side (reader, analyses, lookahead, contexts, facts, rewrites) | Ada, shared by every backend | one copy |
| a backend that writes the parser | `hbnf_c.adb` 13,122 lines, `hbnf_ada.adb` 7,149, `hbnf_zig.adb` 6,224, `hbnf_rust.adb` 5,446 | one copy **per language** |
| the text those backends write | 71 templates (45 of them C's, 9 Rust, 8 Zig, 9 Ada) and, in the Ada, about 2,240 (C), 1,310 (Ada), 956 (Zig) and 763 (Rust) literal `Append` calls | mixed into the Ada |
| the wire emitters | `hbnf_wire-{c,rust,zig,ada_lang}.adb` | one more copy per language |
| a layout | `layouts/NAME/layout.hbnf` + headers (`tailq`, `rb`): a directory read as hbnf holding a `layout_ops` block of C; `ast` and `tape` are Ada in the generator, and no layout file has a rewrite rule | a directory, not yet a rewrite grammar |

So a fifth language costs a fifth 5,000-line Ada file, and every feature (R686 to R702 this month) is written once per language.  That
is the opposite of the goal.  The four backends are not four implementations of four ideas: they are four lowerings of one parsing
algorithm (ordered choice with rollback, repetition, ranges, literals, calls, contexts, facts, rewrites, emits).  The seam to cut is
there.

## A language directory

A language is `languages/<lang>/`, installed beside `layouts/` and `builders/` (R613, R614, R617) and overridable per project.  What R703
and R704 decide: the directory holds the target language's grammar together with an epilogue of native code, compiled to a standalone
`.o` that hbnf links in; the hbnf files in it do what grammar rewrites can, the rest is `.o` files; the user chooses their `languages/`
as they choose their `layouts/`, with no trust model.  **The file names and contents below are the implementer's proposal, details
tbd**:

```
languages/rust/
    grammar.hbnf      the grammar OF the target language (Rust's own syntax), so hbnf can parse a native block: find its closing
                      `}` properly, and say whether it is Rust (replacing the keyword guess that warns today)
    lower.hbnf        the language transformer: rewrite rules (`->`, `=>`, `=>>`) from the IR (the operations below) into Rust text (R608)
    epilogue.c        the native code the rewrites need and hbnf rules cannot say (escaping, identifier rules, formatting)
    build.hbnf        how hbnf makes it: compile lower.hbnf with the C backend, add the epilogue, produce the .o
```

The Ada core stops writing any language.  It reads the grammar, runs the analyses it already runs, and produces **one language-neutral
description of the parser**: the list of typed operations.  The layout grammar and then the language grammar turn that list into text.

### The operations: hbnf-ir (what the four backends already agree on)

The author's names for them are **hbnf-ir** and **hbnf-ops** (either); the file that defines them would be **`irops.hbnf`**: the
roughly forty operations needed to implement a parser from hbnf grammar rules.  The list is *details tbd*; the count below is the
implementer's, taken from the emitters: `rule(name, result type)`, `seq`, `choice(branches)` with the rollback marks, `repeat(min,
max)`, `lit(text, case)`, `range(set)`, `call(rule, args)`, `ahead(not/and)`, `except`, `set_field(path)`, `list_push`, `ctx_add/has/mark/reset`,
`fact_put/get`, `rewrite(template, restart|continue)`, `emit(code)`, `where(code)`, `bind(code)`, `action(rule, code)`, `scan(name, code)`,
`fail(expected)`, `skip_ws`, `col_test`, plus the type side `struct`, `enum`, `list`, `scalar`, `alias` with `field` and `variant`.  About
forty.  The C emitter already has most of them as separate procedures (`Emit_Seq`, `Emit_Alt`, `Emit_Repeat`, `Context_Runtime`, `Emit_Bind`).

### What goes in the language directory

1. **Templates as rewrite grammars** (R608, R710): the 71 Mustache templates become rewrite rules in the language's grammar, a few lines
   per operation.
2. **The epilogue** (R609): native code beside the grammar, compiled with it into the language's `.o`.  The same mechanism serves "native
   code outside the grammar" (R619: a semantic pass or error reporter linked in) and "a new language".
3. **Native blocks go out as written** (R701): `%emit`, `%where`, `%bind`, `%action`, `%scan` are text the language grammar places where
   the operation says; the `language` line picks the language.  With the language's own `grammar.hbnf` hbnf parses the block, which
   finds its end exactly and lets the mismatch warning try each installed language's grammar instead of counting keywords (R703).

### Two jobs for a language directory (the author, 2026-11-14)

1. **Parsing the language inside native blocks** (`grammar.hbnf`): where a `%emit`/`%where`/`%bind`/`%action`/`%scan` block ends, and
   which language it is written in.
2. **Being a backend** (the language transformer and the epilogue's `.o`): the roughly 40 operations needed to parse regular hbnf, written
   out in the backend language for compilation.

The two are independent: a language may have the second without the first (blocks then go out unchecked, as today).  The layouts and the
languages are two stages of one pipeline, in that order: the layout transformer (stage 2) runs first on the IR, the language
transformer (stage 3) second.  Both are directories of rewrite grammars chosen and overridden in the same way.

## The implementer's proposal for loading (not decided, details tbd)

R703 says hbnf itself loads or links the `.o` "using a standard interface"; R712 says the `.o` files may be linked in rather than
interpreted.  The following is one way to do it, written by the implementer; it is not a decision.

A language exports a fixed C-ABI interface, found in `--languages=DIR`, `$HBNF_LANGUAGES`, the project, then `/usr/share`, as layouts are:

```
const hb_lang_info *hb_lang_info(void);            /* name, file extension, interface version, capabilities (has goto, closures) */
int  hb_lang_begin(hb_ctx *c, const hb_unit *u);   /* a unit: the grammar's name, options, its language line, preamble/epilogue text */
int  hb_lang_op(hb_ctx *c, const hb_op *op);       /* one operation of the list, in order; the language appends text through c */
int  hb_lang_end(hb_ctx *c, hb_out *out);          /* the finished files (a parser, a header, a build file) */
```

`hb_op` is a tagged record (kind, name, type, children, flags, the native-code text); `hb_ctx` gives the language the services the core
has already (names of rules, types, the analyses: nullable sets, first sets, which rules recurse) so the language does not recompute them.
`hb_lang_info` lets the core ask what a language can do (`has_goto`, `has_closures`, `has_exceptions`), so the core picks the shape of
`choice` and `repeat` that the language lowers cleanly.  A per-operation callback is one reading of "a standard interface"; a form in which
the language grammar rewrites the whole operation list is closer to R708 to R710, and the choice between them is *details tbd*.

- **Static builds cannot `dlopen`.**  The shipped `./hbnf` and the container builds are static.  Options: a dynamically linked `hbnf`
  (glibc) that loads `language.so` at run time, or a static `hbnf` that links every `languages/*/language.o` present at build time
  (drop-in then means rebuild), or hbnf builds and loads on demand.  The implementer's recommendation: a dynamic `hbnf` for installs and
  development, the static one kept for the bootstrap.  Not decided.
- **Bootstrapping:** the C language must exist to compile any language, so `languages/c` would also be linked statically into hbnf.

## The path (the implementer's, each step keeps the suite green and the output byte-identical)

1. **Name the operations.**  Refactor `hbnf_c.adb`'s emission into a list of operations plus a lowering, in the C backend only (C first).
   Gate: the generated C of every grammar in `corpus/` and `tests/` is byte-identical before and after.  This is the step that decides
   whether the idea holds; it is also pure restructuring, so it is safe.
2. **Write the C language transformer as `languages/c/`** (rewrite rules plus an epilogue), compiled by hbnf's C backend to an object
   linked statically into hbnf as the bootstrap language.  `hbnf_c.adb` shrinks to the operations.  Gate: byte-identical again.
3. **Make the layouts rewrite grammars over the operations** (stage 2: `tailq`, `rb`, and `ast` and `tape`, which are Ada today).
4. **Port Rust to it** (the smallest: 5,446 lines).  Gate: output identical, the Rust suites unchanged.  Then Zig, then Ada.  Each port
   deletes its `hbnf_<lang>.adb`.  The wire emitters follow the same path.
5. **Add a language with no Ada**: Go, Python or Java as a `languages/<lang>/` directory only, proved by the corpus differential tests.
   This is the acceptance test for the whole design.
6. **`build.hbnf` and the loader details** (R609 to R616): per-language build, install under `/usr/share`, project overrides.

The order of the steps is the implementer's; the author decides the order of the work as a whole (R703: the C preprocessor first, then
this revision).

## Risks (the implementer's)

- Step 1 is the hard step: the four emitters differ where the languages differ (Rust closures and `?`, Zig labelled blocks, Ada gotos and
  nested subprograms, C gotos), so the operations must be at the level where all four lower cleanly, which may be lower than listed (an
  operation like `choice` may need to say whether the language has `goto`, or expose the retry structure).  The C emitter's 13,000
  lines are mostly this variety, not noise.
- Performance: C generated code is hand-tuned (jump tables, the `parse_core_X` retry wrapper, compact nodes); the transformers must not
  lose that.  `bench/` before and after each step.
- Size: this is several slices of the size of the whole preprocessor effort, and it competes with it.

## What the implementer builds next

Until step 1 exists, a new feature is written in C first and in the others only when asked, and says so.  The preprocessor (`#`, `##`,
`__VA_ARGS__`) is C-grammar work and is unaffected.

## Decided 2026-11-14 (R703, R704, R708 to R712)

- The pipeline has three stages in this order: front end (the IR of about forty operations), layout transformer, language transformer
  (R708); layouts are rewrite grammars over the IR (R709); languages are rewrite grammars chosen by one emitter back end, replacing the
  Mustache templates and the per-language emitters (R710); the main mechanism is `->`, `=>`, `=>>`, and `%emit` stays for smaller things
  (R711); the grammars may be compiled to `.o` files and linked in (R712).
- Reading B: hbnf itself loads or links the language's `.o` (R703).
- The mismatch warning for native code becomes a real parse with each installed language's grammar, replacing the keyword guess of
  `Guess_Language` in `hbnf_compilable.adb`.  The guess stays until those grammars exist (R703).
- The hbnf files in a language directory do what grammar rewrites can; the rest is `.o` files that hbnf links in.  The user chooses their
  `languages/` as they choose their `layouts/`: no trust model (R704).
- Order: the C preprocessor first (`#`, `##`, `__VA_ARGS__`, `__LINE__`/`__FILE__`, `#include`), then this revision (R703).
- Details tbd: the operation list, the file layout of a language directory beyond R703 and R704, how the `.o` files are built and loaded,
  whether layouts nest under languages (R614).
