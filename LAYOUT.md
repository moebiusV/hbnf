# Layout targets: one grammar, the codec tables and the charts

*A prototype.  What is built is marked **built**; what is only designed is marked **design**.*

The author's words: "hbnf itself should have a grammar that 'transforms' the opcodes; perhaps what i mean by that is, a
custom layout, so the one grammar matches the opcodes and the bit layouts, but what is emitted can be either the
assembler/linker or the svg charts."  And, when the question of how came up: this is where rewrite rules and text
transforms "come into their own".

The name: `--layout=` already exists and means the storage of the parse tree (`layouts/tailq`, `layouts/rb`).  This
facility is a **target**: `--target=NAME`.  What a target reads is the **layout model** of the bit rules: for every way a
record can be laid out, the rows of the drawing and the fields in them, with widths, places, roles and labels.

## 1. What is there today (verified in the source at 9884a84, 2026-11-04)

| thing | state |
|---|---|
| bit rules (`WIRE.md`): fields `name:N`, constants, enums `"x"@N`, `bitsof`, alternatives, guards | **built**, C/Rust/Zig/Ada readers and writers (HBNF_Wire, hbnf_wire-*.adb) |
| `%action{ }`, `%emit{ }`, `%scan{ }` | **built**, but each is a block of the *target language's own code* copied through: C, Rust, Zig or Ada.  `%emit` in the wire layer runs on a copy of the record before it is written; in a text rule it runs at recognition.  They are hooks, not a text-generation language: no loops over matches, no names for the matched pieces other than the language's own, no gensym |
| `=>` | the lexer has the token (`T_Arrow`) **only** for `=> grammar(NAME)`, switching to another grammar's rules (`hbnf_grammar.adb`).  There is **no rewrite of a matched phrase into another phrase**; `hbnf_schema.hbnf` has no `=>` at all.  `METACOMPILERS.md` lessons 2 to 4 (gensym in `%emit`, `=>` rewriting, cases on the shape of a match) are **described only** |
| `macros <rule>` (`ABNF.md`) | **built**, and narrow: for the statement-at-a-time C parser of a config file, a statement the rule matches defines `$name`, which later statements expand.  It is not a grammar-level rewrite |
| templates | `templates/*.tmpl`: 67 files, 64 182 bytes, rendered by **`HBNF_Template`, in the hbnf tree** (hbnf_template.adb, 500 lines) over the parser hbnf makes of `grammars/template.hbnf`.  **mustache-ada has not been a dependency since f1ab596 (2026-10-31)**; `libhbnf.gpr` has no `with "mustache.gpr"`.  (The pdp64 repository's `tools/build-hbnf.sh` still installs the mustache-ada `.apk` files: stale, and droppable.) |
| what the templates use | 236 tags in all: 209 raw holes `{{&x}}`, 13 sections (`items` x9, `sep` x2, `rep`, `first`), 1 inverted section (`^items`), 14 closing tags.  No escaped tag, no `{{{`, no dotted name, no partial, no comment, no delimiter change.  59 of the 67 templates have no section at all.  The loops are one deep over a list the Ada code has already built, and the flags (`sep`, `first`, `rep`) are filled by the Ada code too |
| a table of leaves | not there: no template, no backend |

What the Mustache subset therefore asks of a replacement is small (section 7), and what the backends ask is large:
about 50 `Fill`/`Render_File` call sites build the view in Ada (`hbnf_c.adb` 27, `hbnf_ada.adb` 9, `hbnf_rust.adb` 9,
`hbnf_zig.adb` 8).  The intelligence is in the Ada; the templates are the boilerplate around it.

## 2. What "a custom layout" means: what the chart and the tables need that bit rules do not carry

A bit rule says how wide a field is and what values it may have.  A chart or a codec table also needs:

| need | where it comes from |
|---|---|
| the **role** of a field: prefix (opcode), sub-opcode, register, immediate, displacement, condition, scale, padding... | for colouring and a legend; for the tables, which fields are operands |
| a **display name** and a **note** | `Rd`, `disp`; "signed, units of 8 bytes"; the mnemonics a sub-opcode field selects |
| a **title** per alternative | "LDU.B28: load with a 28-bit displacement" |
| the **unit of drawing** | 16 bits to a row (a *parcel*), bit 15 at the left, rows in order |
| **which constants are the prefix code** | the first constant of a leaf; a constant is drawn digit by digit, an operand as a labelled box |
| **pieces of one field** | a displacement split into two places by the encoding is one logical field with two runs |
| **trailing literals** | a field whose length is a count, drawn as a dashed row |

Everything else (widths, constants, signedness, alternatives and their guards, nesting) the bit rules already say.

## 3. How the grammar carries it (**built**)

Annotations in the same file, in the notation of the rule, after the thing they describe:

    leaf-LDB28 = 0b11000010 %prefix  sub:4 %sub("sub-opcode")  o2-r:4 %reg("Rd")
                 o1-base:4 %reg("Rb")  o1-d:28s %disp("disp" "signed, bytes")
                 %title("LDU.B28: load with a 28-bit displacement")

* `%role` or `%role("label")` or `%role("label" "note")` after a field or a constant.  A role is any lower-case word
  (letters and hyphens, two or more; none of the words hbnf reads for itself); the target decides what it looks like.
* `%title("text")` or `%title("text" "note")` anywhere in an alternative.
* `%TARGET{ template }` at the end of a rule: that rule's own transform for the target of that name (section 6).

**Why this form and not another.**  hbnf already puts per-rule extras after the pattern, as `%action{ }`, `%emit{ }`,
`%scan{ }` and `%label`.  `%words` after a field are the same shape, need no new token (the lexer reads `%` and a word
already), and cannot clash with a field (`name:4`) or with ABNF's `%d13.10` (a role has no digit).  Three alternatives were
weighed:

* *Structured comments* (`;@ reg "Rd"`) keep a grammar valid for an older hbnf, which is attractive (the pdp64 pipeline
  runs older binaries), but a comment that changes the output is a second language hiding in a first one, `hbnf --lint` and
  the reader cannot check it, and a typo is silent.  Rejected.
* *A separate `%layout` block* (`layout leaf-LDB28 { o2-r: reg "Rd" ... }`) keeps the rule clean but names every field a
  second time, so it drifts: the very thing a single source is for.  Rejected for fields; a block is the right place for
  file-level settings (the unit of drawing, a table of default roles by name pattern), which are not built (`--unit=N` on the
  command line stands in).
* *A suffix on the name* (`o1-r:4<reg,Rd>`) fights the `name:[expr]` and `name:(a|b)` forms of the field syntax.

An annotation changes nothing a backend generates: `tests/target.sh` generates C, Rust, Zig and Ada from the annotated
mini example and from the same file with every annotation stripped, and the outputs are identical.

**Limits.**  A `%role` may follow only a field or a constant of the bit layer (a text element has no layout).  A label names a
logical field: fields of one chart that carry the same label are the pieces of one field (the pdp64 grammars split a
displacement into `o1-d-1` and `o1-d-2`; both say `%disp("d1")`); the table target keeps their runs together.  The text of
`%TARGET{ }` is read the way hbnf reads a code block (balanced braces, strings and comments), so a template with an
unbalanced quote needs the quote written twice or avoided; a raw block form would be better (design).

## 4. The model (**built**) (hbnf_layout.adb)

`HBNF_Layout` expands the bit rules into **charts** (a choice of rules, `leaf:( a | b )`, or of alternatives, `body:( ?(g1) x | ?(g2) y )`, is multiplied out; a named rule is inlined, so `insn` over 270 leaves is 270 charts and the r20
`insn` over 21 body alternatives is 21), then lays each out:

    chart   name title note rule index unit unit_name bits fixed nparcels nrows
            guards[ g gi ]  nguards  left cell hdr          (the drawing's geometry, so every target agrees)
            prefix_bits prefix_value
            rows[ n label var  pieces[ name label short note role w pos hi lo parcel const var signed expr split range
                                       cont_before cont_after  value digits[ d i pos ] ] ]
            roles[ role ri ]  nroles
            places[ name label role bits signed nruns run0  runs[ parcel hi len ] ]   nplaces place0

A row is `--unit` bits (default 16, `--unit-name`, default `parcel`); a field that crosses a row is split into pieces with
the field's own bit range (`[27:16]`); a field of unknown size (`name:[expr]`, `name:*u8`, `bits(expr)`, a list, a text
rule) is a dashed row of its own and ends the fixed layout.  `places` is the same layout seen as a codec wants it: a
field (or the fields that share a label) and the runs of bits it occupies, most significant first, with running indices
into one pool (`run0`, `place0`).

The existing backends do not consume this model: they read the wire tree (`HBNF_Wire.Grammar`: items with kinds, widths,
guards), which is the model's source.  The chart model is a *view* of the same tree with the geometry applied, so adding a
backend that consumes it (Markdown tables, graphviz) is a directory of templates, not a new Ada unit.

## 5. Targets and the template language (**built**)

    hbnf grammar.hbnf --target=svg      [--targets=DIR] [--out=DIR] [--unit=16] [--unit-name=parcel] [--chart-root=RULE|all]

A target is a directory `targets/NAME/` of `*.tmpl`.  `NAME.EXT.tmpl` is rendered once to `NAME.EXT` with the whole model
(`charts`, `nchart`, `source`, `unit`); `chart.EXT.tmpl` is rendered once per chart to `<chart>.EXT`, the chart being the
innermost scope.  Without `--out` the files go to standard output, each after a line `%%% NAME`; with `--out=DIR` they are
written there.  The output is sorted and carries no clock, so it is byte-stable (`tests/target.sh` keeps fixtures and the
digests of the pdp64 tables).  `--chart-root=` names the rule(s) to expand (comma list; `all`: every bit rule nothing
else names); the default is the first rule, hbnf's own convention.  (`--root=` is not used: it is ignored for bit-only
reading, one of the gaps below.)

The templates are the existing Mustache of `HBNF_Template`, plus three things the renderer now has:

* **integer expressions**: a tag whose name starts with `(` is C's integer arithmetic over the numbers in scope, read by
  the wire layer's own expression reader: `x="{{(left+pos*cell)}}"`, and as a condition `{{#(w>1)}} ... {{/(w>1)}}` (taken
  when not zero), `{{^(w>1)}}`.  No blank may stand inside the tag (the template grammar reads a name up to a blank).
* **the place in a list**: inside a list section, `_i` (from 0), `_n`, `_first`, `_last`.
* **a rule's own transform**: `%TARGET{ ... }` in the grammar (section 3) is rendered in place of the target's `chart.EXT.tmpl`
  for the charts of that rule.

### The svg target (`targets/svg`)

One SVG per chart and an HTML index.  A 16-bit row is 576 px wide (36 px a bit; a wider unit is narrower per bit so the
chart stays that wide); bit numbers over the edges of each field; constants drawn a digit to a bit; operands as labelled
boxes coloured by role; a field split across rows shows its range `[27:16]`; a variable field is a dashed row; guards are
printed under the title; a legend of the roles in use.  Colours are CSS variables with a `prefers-color-scheme: dark`
set (checked by reading the CSS; a dark rendering was not produced: headless Chrome did not apply the media query to a
standalone SVG).  The text is plain `<text>`, so it converts with any renderer that reads CSS classes; renderers that
ignore `var()` (ImageMagick's built-in one) draw it black: use a browser or rsvg-convert.

### The c-tables target (`targets/c-tables`)

`tables.c.tmpl` writes three arrays from the model: `R[]` (the runs: parcel, high bit, length), `P[]` (the places: width,
number of runs, first run) and `LF[]` (the leaves: prefix, prefix length, parcels, first place, number of places, name).
It is checked against the independent generator of the pdp64 repository (`tools/mkenc.py` over `tools/encgram.py`): for
every one of the 270 leaves of pdp64/16 and the 268 of pdp64/32 the prefix, its length and the runs of every field are equal.
Order differs (see the limits); `tests/target.sh` keeps the digest of the output.

What it does **not** do, and what is missing in hbnf for it (the "table of leaves" gap):

1. *indexes across tables*: the codec's pools are deduplicated (`S[]` the operand specs, `FS[]`, `FM[]`) and a mnemonic's
   candidate forms are ordered for the assembler, and the mnemonic table is sorted by name.  A logic-less template cannot
   deduplicate, sort or look a name up.  The model would need `unique-by`, `sort-by` and `index-of` (as list operations
   the model applies, not the template) or the transform language would need them.
2. *a field's operand index and part index*: pdp64 writes them into field names (`o2-base`).  The model has the name and a
   label, not a number; an annotation `%at(2 1)` (or a role with arguments) would carry them.
3. *the order of places*: mkenc lists operands before the sub-opcode; the model lists them in the order of the bits.
4. *a field typed by an enum* (`sub:4 of sub-LDU-B28-1`, gap 1 of `docs/encoding-work/hbnf.md`): the mnemonics of a leaf are
   in a second rule joined by name; the model does not see them, so the note of a sub field carries them as text.
   With the typed field the model would hold the list and a table could emit `nmn`.

So the table target **replaces the part of `mkenc.py` that is arithmetic over layout** (runs, places, prefixes: about a third
of the file), not the part that is indexing and ordering.  Section 8 says what finishing it takes.

## 6. Transforms, rewrite rules, and the direction (**design**, with the prototype as its first step)

The author's direction is that rewrite rules and text transforms are the mechanism, and the Mustache templates are to go.
What the prototype shows is the smallest step that is already *the same mechanism*:

* a **transform is a text pattern with holes, attached to a rule of the grammar** (`%svg{ ... }`, built), chosen by the
  **target** named on the command line;
* the holes are filled from the **match** (the model of that rule: its fields, roles, labels, widths), with expressions
  for the arithmetic and conditions on the shape of the match (`{{#(w>1)}}`, `{{#const}}`: cases on the shape, lesson 4),
  repetition over the alternatives, fields and runs, and the list position for separators (built);
* an **output per match** (one file per chart) and one per grammar (the index) (built);
* a **unique name per match** (gensym, lesson 2): every piece has `uid` (built); a loop or a conditional in the *output
  language* is then written with the transform's own sections, not by the emit code of the target language.

What is not built and would be next, in order of use:

1. **Rules whose right-hand side is a phrase of the same grammar** (`=>`, lesson 3): `leaf-LDB28 => ldu(sub, o2, o1)`: the
   instruction as the assembler writes it, so that one grammar also defines the *assembly syntax* of an instruction as a
   rewrite of its bit layout, and `sub-FORM-K` need not be a second rule joined by name.  This needs the reader to keep the
   `=>` right-hand side as a tree and a rewriter over trees; nothing like it exists today and it is the largest item.
2. **Cases on the shape of a match as pattern rules**: `%svg[role == prefix]{ ... }` on a field, rather than a flag tested in the
   template.  The prototype tests flags (`const`, `var`, `split`) with sections.
3. **Transforms on text rules**: today only bit rules are in the model.  The same model applies to a text rule's alternatives
   (railroad diagrams, documentation of a notation), which is the same facility.

## 7. Transform language against a richer data model for the Mustache templates

*Option A: keep Mustache and expose a richer model.*  Mustache is logic-less on purpose: it cannot add, compare or number, so
every derived value the output needs (`x`, `width`, `hdr`, the `first` flag, the cumulative run index) must be put into the
model by Ada.  That is what happens today (`sep`, `first`, `rep`, and 50 call sites that build the view) and it is what the
first version of this prototype would have needed for an SVG: `x`, `y`, `cx` for every piece, in the model, so that the
model knows about drawing.  The advantage: a very small engine, templates that cannot loop forever, and the existing 67
templates untouched.  The cost: each target costs Ada code, which is exactly what the author wants to avoid.

*Option B: a transform language*: the template language plus expressions and conditions and list position, and per-rule
transforms in the grammar.  The cost: the language is a (small) programming language and must be specified and tested
(integer arithmetic only, no loops except over the model's lists, no recursion: it always terminates).  The gain: a target
is a directory of text; the model stays geometry-free except for what several targets share (the rows and pieces, `cell`).

*They converge*, and the prototype is that convergence: the transform language here **is** the template language of
`HBNF_Template` with three additions of about 120 lines of Ada (the expression evaluator reuses `HBNF_Wire.Parse_Expression`; the
list scope is 20 lines).  Subsumption of the old templates is therefore not an argument but a fact: every `.tmpl` of the
tree is a valid transform, and `tests/xform.sh` shows two of them (`ada_enum`, `rust_enum`, the ones that use `sep`, `rep`
and `first`) ported to say with `_i` what the Ada code now says by filling `sep` and `first`, and 400+ runs over every
grammar of the tests and `grammars/` come out byte for byte identical.

**Recommendation: B, as an extension of the engine that is already in the tree, not a new engine.**  `mustache-ada` is already gone;
what remains of "Mustache" is a name and a parser grammar of 25 lines.  The syntax the prototype settles for (`{{(expr)}}`,
no blanks inside a tag) is a compromise with that grammar; a clean transform syntax would have its own grammar,
`grammars/xform.hbnf`, in hbnf's own notation, generated into `HBNF_Xform_Syntax` by the same `scripts/gen-template-syntax.sh`
(the bootstrap is the one that exists), with `{{ expr }}` allowed to hold blanks, `{{#each charts}}`, `{{#if (w>1)}}` and a closing
`{{/}}`.  Estimated at two days with the tests.  The 67 templates then migrate mechanically (section 8) or stay, since the new syntax can be a
superset.

## 8. Migration of the template set

Inventory in section 1.  A port of one template is a rewrite of its tags; the **work** is in the Ada that fills the view.

| step | what | size |
|---|---|---|
| 0 | keep all 67 templates as they are: the language is a superset | done |
| 1 | the 8 templates with `sep`/`first`/`rep` use `_i` and `_first`; delete the flags from the Ada that fills them (4 call sites) | an hour; `tests/xform.sh` is the check |
| 2 | the 59 templates with only holes stay holes.  Moving *their* logic out of Ada means giving the model the shape (fields, kinds) and writing the loops in the template: for the struct and enum templates (`*_struct`, `*_enum`, `*_list_entry`: 12 files) this is a matter of exposing `Info.Members` as `items[ field type ]`, which the Ada already builds | 2 days |
| 3 | the parser templates (`c_parser`, `c_statements`, `c_macros`, `rust_parser`...: about 45 KB of the 64) are code with holes filled by emitted *fragments* assembled in Ada (`hbnf_c.adb` is 12 400 lines, most of it the choice of what to emit).  Porting them to rewrite rules means expressing that choice as cases on the shape of each element: the work of the backends themselves | weeks per backend; and it is the part that would change hbnf's architecture, so it should wait for `=>` (section 6) |

Recommendation: do 0 and 1 now (they remove the flags), 2 with the next backend, leave 3.

## 9. Gaps found in hbnf (beyond the four of `docs/encoding-work/hbnf.md`)

* `--root=` is ignored for bit-only grammars and checked against text rules (`the schema has no rule of that name`); the
  prototype adds `--chart-root=`.  Gap 3 of the pdp64 notes, still there.
* a bit field cannot be typed by an enum (gap 1): the model cannot know which mnemonics a sub-opcode selects.
* rule names cannot hold `.` or `/` (gap 2): chart file names come from the `-`/`_` spellings, not the optimiser's names.
* the template grammar reads a tag name up to a blank, so an expression cannot contain one.
* the code-block lexer is C-aware, so a `%TARGET{ }` template with an odd number of quote characters cannot be written.
* names in the wire tree have `-` turned into `_` (the code generators need that); a target wants the author's spelling,
  which the prototype restores by turning `_` back (so a rule that the author spelled with `_` is shown with `-`).
* not built: the unit of drawing in the grammar (`--unit` stands in), the default roles by name pattern (the pdp64
  annotation is a script, `examples/pdp64/annotate.py`, run once), per-rule `%TARGET{}` for non-chart templates, a `md`/`dot` target.
