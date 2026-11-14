# languages/: a language is a directory

Draft for the author's reaction, 2026-11-14.  Nothing here is built.  It follows R608 to R620 of `decision-register.md` and the
author's messages of 2026-11-14: "the original goal for hbnf is to support a bunch of languages besides the current 4", and "the
languages/ hbnf dir would have grammar together with epilogue that has all the native code needed to compile standalone .o file, then
the ada could just link in the .o using a standard interface, which would make supporting another language just a matter of dropping
another language into the languages/ dir".

## Where it stands

| part | today | size |
|---|---|---|
| the grammar side (reader, analyses, lookahead, contexts, facts, rewrites) | Ada, shared by every backend | one copy |
| a backend that writes the parser | `hbnf_c.adb` 13,117 lines, `hbnf_ada.adb` 7,149, `hbnf_zig.adb` 6,224, `hbnf_rust.adb` 5,446 | one copy **per language** |
| the text those backends write | 71 templates (45 of them C's) and about 700 to 2,000 literal `Append` calls per backend | mixed into the Ada |
| the wire emitters | `hbnf_wire-{c,rust,zig,ada_lang}.adb` | one more copy per language |
| a layout | `layouts/NAME/layout.hbnf` + headers: a directory, read as hbnf, found by `--layouts` or `$HBNF_LAYOUTS` | already the right shape |

So a fifth language costs a fifth 5,000-line Ada file, and every feature (R686 to R702 this month) is written once per language.  That is
the opposite of the goal.  The four backends are not four implementations of four ideas: they are four lowerings of one parsing
algorithm (ordered choice with rollback, repetition, ranges, literals, calls, contexts, facts, rewrites, emits).  The seam to cut is
there.

## The idea

A language is `languages/<lang>/`, installed beside `layouts/` and `builders/` (R613, R614, R617) and overridable per project:

```
languages/rust/
    grammar.hbnf      the grammar OF the target language (Rust's own syntax), so hbnf can parse a native block: find its closing
                      `}` properly, and say whether it is Rust (replacing the keyword guess that warns today)
    lower.hbnf        the lowering, written as hbnf: a set of rewrites of hbnf-ir (the operations below) into Rust text (R608, templates as hbnf)
    epilogue.c        the native code the lowering needs and hbnf rules cannot say (escaping, identifier rules, formatting)
    build.hbnf        how hbnf makes it: compile lower.hbnf with the C backend, add the epilogue, produce language.so
```

hbnf compiles `lower.hbnf` + `epilogue.c` to a standalone `.o` (a `.so`) **with its own C backend**, and **hbnf itself loads it**
through one fixed interface.  So a language is built by hbnf from hbnf, and the Ada core never contains a language.

The Ada core stops writing any language.  It reads the grammar, runs the analyses it already runs, and produces **one language-neutral
description of the parser**: a list of typed operations.  The loaded language turns that list into text.

### The operations: hbnf-ir (what the four backends already agree on)

The author's names for them are **hbnf-ir** and **hbnf-ops** (either); the file that defines them would be **`irops.hbnf`**: the roughly forty operations needed to implement a parser from hbnf grammar rules.  A language's
lowering (`lower.hbnf`, with the layouts) is then **rewrites of hbnf-ir** into the backend language, the same `=>` rewrite machinery the
C preprocessor uses; what a rewrite cannot say goes to the `.o`.


Counted from the emitters, not invented: `rule(name, result type)`, `seq`, `choice(branches)` with the rollback marks, `repeat(min,
max)`, `lit(text, case)`, `range(set)`, `call(rule, args)`, `ahead(not/and)`, `except`, `set_field(path)`, `list_push`, `ctx_add/has/mark/reset`,
`fact_put/get`, `rewrite(template, restart|continue)`, `emit(code)`, `where(code)`, `bind(code)`, `action(rule, code)`, `scan(name, code)`,
`fail(expected)`, `skip_ws`, `col_test`, plus the type side `struct`, `enum`, `list`, `scalar`, `alias` with `field` and `variant`.  About
forty.  The C emitter already has most of them as separate procedures (`Emit_Seq`, `Emit_Alt`, `Emit_Repeat`, `Context_Runtime`, `Emit_Bind`).

### What goes in the language directory

1. **Templates as hbnf** (R608): the 71 Mustache templates become `lower.hbnf` rules, a few lines per operation.
2. **The epilogue** (R609): native code beside the grammar, compiled with it into the language's `.o`.  The same mechanism serves "native
   code outside the grammar" (R619: a semantic pass or error reporter linked in) and "a new language".
3. **Native blocks go out as written** (R701): `%emit`, `%where`, `%bind`, `%action`, `%scan` are text the lowering places where the
   operation says; the language line picks the language.  With `grammar.hbnf` hbnf parses the block, which finds its end exactly and lets
   the mismatch warning try each installed language's grammar instead of counting keywords.

### The standard interface (the author: hbnf itself loads the `.o`)

A language exports a fixed, C-ABI interface that hbnf loads at run time (a `dlopen` of `languages/<lang>/language.so`, found in
`--languages=DIR`, `$HBNF_LANGUAGES`, the project, then `/usr/share`, as layouts are):

```
const hb_lang_info *hb_lang_info(void);            /* name, file extension, interface version, capabilities (has goto, closures) */
int  hb_lang_begin(hb_ctx *c, const hb_unit *u);   /* a unit: the grammar's name, options, its language line, preamble/epilogue text */
int  hb_lang_op(hb_ctx *c, const hb_op *op);       /* one operation of the list, in order; the language appends text through c */
int  hb_lang_end(hb_ctx *c, hb_out *out);          /* the finished files (a parser, a header, a build file) */
```

`hb_op` is a tagged record (kind, name, type, children, flags, the native-code text); `hb_ctx` gives the language the services the core
has already (names of rules, types, the analyses: nullable sets, first sets, which rules recurse) so the language does not recompute them.
`hb_lang_info` lets the core ask what a language can do (`has_goto`, `has_closures`, `has_exceptions`), so the core picks the shape of
`choice` and `repeat` that the language lowers cleanly.

Consequences to settle before step 2:

- **Static builds cannot `dlopen`.**  The shipped `./hbnf` and the container builds are static.  Options: a dynamically linked `hbnf`
  (glibc), or a static `hbnf` that links every `languages/*/language.o` present at build time (drop-in then means rebuild), or hbnf
  builds and loads on demand.  My recommendation: dynamic `hbnf` for installs and development, static kept for the bootstrap.
- **Bootstrapping:** the C language must exist to compile any language, so `languages/c` is also linked statically into hbnf.

## The path (each step keeps the suite green and the output byte-identical)

1. **Name the operations.**  Refactor `hbnf_c.adb`'s emission into a list of operations plus a lowering, in the C backend only (C first).
   Gate: the generated C of every grammar in `corpus/` and `tests/` is byte-identical before and after.  This is the step that decides
   whether the idea holds; it is also pure restructuring, so it is safe.
2. **Write the C lowering as `languages/c/lower.hbnf` + `epilogue.c`**, compiled by hbnf's C backend to `language.o`, linked statically
   into hbnf as the bootstrap language and loadable like any other.  `hbnf_c.adb` shrinks to the operations.  Gate: byte-identical again.
3. **Port Rust to it** (the smallest: 5,446 lines).  Gate: output identical, the Rust suites unchanged.  Then Zig, then Ada.  Each port
   deletes its `hbnf_<lang>.adb`.  The wire emitters follow the same path.
4. **Add a language with no Ada**: Go, Python or Java as a `languages/<lang>/` directory only, proved by the corpus differential tests.
   This is the acceptance test for the whole design.
5. **`build.hbnf` and the dynamic loader details** (R609 to R616): per-language build, install under `/usr/share`, project overrides.

## Risks, stated

- Step 1 is the hard step: the four emitters differ where the languages differ (Rust closures and `?`, Zig labelled blocks, Ada gotos and
  nested subprograms, C gotos), so the operations must be at the level where all four lower cleanly, which may be lower than I listed (an
  operation like `choice` may need to say whether the language has `goto`, or expose the retry structure).  The C emitter's 13,000
  lines are mostly this variety, not noise.
- Performance: C generated code is hand-tuned (jump tables, the `parse_core_X` retry wrapper, compact nodes); the lowering must not lose that.
  `bench/` before and after each step, pinned to CPU 5.
- Size: this is several slices of the size of the whole preprocessor effort, and it competes with it.  The order is yours.

## What this changes in what I build next

Until step 1 exists, a new feature is written in C first and in the others only when asked, and says so (the stopgap note in the
memory file `languages-dir-architecture`).  The preprocessor (`#`, `##`, `__VA_ARGS__`) is C-grammar work and is unaffected.

## Two jobs for a language directory (the author, 2026-11-14)

1. **Parsing the language inside native blocks** (`grammar.hbnf`): where a `%emit`/`%where`/`%bind`/`%action`/`%scan` block ends, and
   which language it is written in.
2. **Being a backend** (`lower.hbnf`, `epilogue.c`, the `.o`): the roughly 40 operations needed to parse regular hbnf, written out in the
   backend language for compilation.  This is the layouts side: `languages/` and `layouts/` are the same kind of directory.

The two are independent: a language may have the second without the first (blocks then go out unchecked, as today).

## Decided 2026-11-14 (R703)

- Reading B: hbnf itself loads the language's `.o`.
- The mismatch warning for native code becomes a real parse with each installed language's `grammar.hbnf`, replacing the keyword guess
  of `Guess_Language` in `hbnf_compilable.adb`.  The guess stays until those grammars exist.
- The hbnf files in a language directory do what grammar rewrites can; the rest is `.o` files that hbnf links in.  The user chooses their
  `languages/` as they choose their `layouts/`: no trust model.
- Order: the C preprocessor first (`#`, `##`, `__VA_ARGS__`, `__LINE__`/`__FILE__`, `#include`), then this revision.
