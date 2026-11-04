# Contexts: where a rule is, what it has, what it is

**Status (reviewed; kept up to date with what is decided and what is built, last 2026-11-03).**  The sections below are the record of how
each point was reached; this table is where it stands.  Under the standing rule, no syntax is implemented before it has been shown and approved.

| Point | State | Where |
|---|---|---|
| Islands: `include "f" as x`, `x.rule`, the dot is scope and never part of a name, strict lookup (a missing name is missing); `^.rule` is the way out, a rule of the including grammar (`^.^.rule` two levels, `^.sql.rule` an island of the parent) | **built** (aff3de9), four backends; tree-sitter refuses a scope that skips white space differently; `^.rule` **built** 2026-11-03 (`tests/upscope.sh`) | 14, 19, stage 1 status |
| Switch `=> grammar(x)`, `=>` the one arrow | **built, phase 1: white space only** (aff3de9), C, Rust, Zig, Ada; tree-sitter refuses a switch | 15, 18, 19, 22, stage 2 status |
| Pattern arguments `phrases("SIZE" "ERROR")` and the literal join `"END-" + K` | **built** (09b966c); used in COBOL as `phrases(W)` and `scope-end(K)` | 21 |
| Two `ws` bugs (a lookahead in `ws`, a group after a literal) | **fixed** (112f19f) | 20 |
| Notation `i"..."`, `s"..."`, `r"..."`, C numbers; the `%` forms kept for the ABNF dialect only | **built** (8328962); the repository's grammars rewritten | 23 |
| `bol` and `eol`, built-in zero-width rules; no `^` or `$` in `r"..."` | **decided 2026-11-03, being built** | 24 |
| `r"..."` with a one-letter rule (`exponent = ir"E"`) in the full COBOL grammar | **a defect, found 2026-11-03, being fixed**; the rule stays code points meanwhile | 23 |
| Keywords as reserved words, without `%` | **decided** as to reserved words; the spellings of `%label`, `%num`, `%action` and the rest are **open**; nothing built | 10 |
| Back-references: `x as K` captures, `$K` matches the same text again (replaces `%as` and `%same`); named only | **decided 2026-11-03**; `%as`/`%same` are built, the new spelling is not | 10 |
| Facts (a rule's own attributes, keyed by name) | **decided yes**; nothing built | 13 |
| Labels (`name:` lines that set the context) | **open**; nothing built | 16 |
| Switch phase 2 (token and scalar overrides: decimal comma, per-region reserved words) and phase 3 (phrase variants in `ast`, the tape case) | **decided design**; not built | 22 |
| `col` and `where (cond)`; `30WS` | **proposed**; `bol` and `eol` come first and cover the line-start cases; `col` 0-based and `where` as a postfix are **to be confirmed** | 24 |
| Fixed-format COBOL as a grammar | **not started**; waits for `bol`/`eol` and `col` | 24 |
| GLR | **allowed** by the scope note, pay only for what is used; not started | RFCPLAN |

COBOL embeds other languages (SQL, CICS, DLI, and JCL near it), its PICTURE clause is a small language of its
own, and its meaning depends on what the data division declared.  C needs the same from a typedef.  YAML and Python
need it from the indentation.  All of these are a rule depending on something outside its own text: a context.
This page names the kinds, lists what hbnf has for each, and offers several ways to write each one that change
BNF as little as possible.

## 1. What hbnf has now

| need | notation today | where it stops |
|---|---|---|
| a different lexical mode (white space, case, tokens) | `whitespace ws`, `whitespace none`, `sensitivity string %i`, `dialect`, one tokens file per mode | the **file**: a mode cannot change inside a rule |
| a name is of some kind | `context types`; `name ? types`; `name ?! types` | the set, until a scope ends |
| a name is added to a kind | `%bind types += decl.name`; `%scope` | the scope |
| a value from outside or from the text | parameters, `binary(N in 1..17)`, `declarator("vars")`, `x %num D`, `%spaces K`, `%col` | the rule that takes it |
| the same text again | `name %as tag` ... `%same tag` | the sequence |
| host code | `%where { code }` | one test |

Three things stand out.  The sigils (`%`, `?`) carry most of it, and the notation reads as code rather than as
a grammar.  A mode belongs to a file, so a language inside a language needs a second file and has no way to say where
it ends.  And one notation (`?`) is used for kind, while a different one (`( )`) carries a value; the grammar's
reader has to know which is meant.

## 2. The three relations

A rule has three different relations to what surrounds it.

- **In a context** (a place).  The rule is read in a mode: SQL inside `EXEC SQL ... END-EXEC`, the characters of
  a PICTURE string, a heredoc, a comment, the data of a JCL step.  The mode brings its white space, its case
  rule, its reserved words, its tokens.  Embedded languages and DSL strings are this.
- **Having an attribute** (a property).  The rule carries a value beside its text: the level number of a data
  entry, the size a PICTURE gives, the indent of a block, the length before a payload.  The value is given to the rule
  from outside (inherited) or made by it (synthesized).
- **Being a kind of thing** (a classification).  The text is accepted because of what it is known to be: a
  typedef name rather than a variable, a condition name rather than a data name, a class name from SPECIAL-NAMES.
  The knowledge is a set that declarations fill.

## 3. Other kinds of context?

Each of these shows up in some language.  Most turn out to be one of the three applied to something else.

| kind | example | which of the three |
|---|---|---|
| position (column, line start) | COBOL fixed-format area A and area B; YAML indentation | an attribute of the place the rule starts |
| nesting depth | nested comments, a bound on recursion | an attribute that counts |
| the same text as before | an XML closing tag, a heredoc end, COBOL `END PROGRAM name` | an attribute that is a piece of text |
| the neighbours of a token | `A - B` against `A-B`, `a>>b` in a template | not context: lookahead and lookbehind (`!`, `&`; lookbehind is missing) |
| a dialect or version set from outside | `>>SOURCE FORMAT`, `-std=c99`, `%YAML 1.1` | a context (in a mode) that a directive sets |
| a size or count | `PIC 9(5)`, `OCCURS 3 TIMES`, a length prefix | an attribute that is a number |
| where the text came from | a copybook, a macro expansion | outside the grammar: a preprocessor's business |
| what is being written | the target syntax of a translation | the output side, not parsing |
| what has been seen so far in this rule | COBOL's data clauses, in any order and each once | a **kind** (a set), kept for the length of one rule |

So the three cover the grammar's side.  Two additions are worth naming because they cut across all three.

- **Extent**: how long it lasts.  A file (today's modes), a rule, a scope (a block), a region (until a
  terminator), or one rule's siblings (the data clauses).  Today only the file and the scope can be said.
- **Direction**: whether it comes in or goes out.  A level number goes out of the rule that reads it and into the
  entries below; a typedef name goes out of a declaration into everything after it.

## 4. What a notation should do

- Change BNF as little as possible, so that a rule with no context reads as the BNF it is.
- Read naturally to a person who has never seen it, without a sigil to learn (`%`, `@`, `$` are what to avoid).
- Cost nothing for a grammar that uses none of it.
- Be one idea, not three: the three relations should look like cases of one thing.

Where hbnf already has a form, the options below reuse it: `( )` for parameters with a domain `N in 1..17`,
`-` as the infix exception operator, `<rule>` as a rule name.

## 5. Options for being **in** a context

**5.1  Say nothing in the rule; let the file carry it.**  Embed a grammar by including it under a name, and refer to
its rules by that name.  The rule syntax does not change.

```
include "sql.hbnf" prefix "sql-"          ; its rules appear as sql-statement, sql-select, ...
exec-sql = "EXEC" "SQL" sql-statement "END-EXEC"
```

The mode (white space, case, reserved words) is the included file's own directives, as now.  New: a prefix on
`include`, which is a directive and not part of a rule.  Missing: where the region ends (see 5.5).

**5.2  A qualified name.**  `include "sql.hbnf" as sql` and then `sql.statement`.  Familiar from every module system;
a dot is free in rule names.  It changes the name syntax slightly.

**5.3  An infix word.**  Reuse the shape of `a - b`: `sql-text in sql` means "read the text of `sql-text` with the
rules of `sql`".

```
picture-clause = ( "PICTURE" | "PIC" ) [ "IS" ] picture-text in picture
```

Reads like English; `in` is already a word of the notation (`N in 1..17`).  The cost is that `in` then means a
mode here and a domain there.

**5.4  A mode as a parameter.**  The hyperrule machinery already passes a word through a rule.  A mode is such a
word: `statement("sql")`, with the file-level directives given per mode (`whitespace("sql") = sql-ws`).

```
mode ::= "cobol" | "sql" | "cics"
exec-sql := "EXEC" "SQL" statement("sql") "END-EXEC"
```

No new syntax at all, only a new use of parameters; the price is that the directives become parameterised too.

**5.5  Where it ends.**  An embedded region ends at text the embedded grammar does not know (`END-EXEC`).  Options:

- a lookahead inside the embedded grammar (`*( !"END-EXEC" token )`), written by hand and already possible;
- an infix `until`: `sql-statement until "END-EXEC"`, a plain-English operator that means the region stops
  where the terminator begins and the embedded rules may not read past it;
- an **island**: capture the region as text, `region = text until "END-EXEC"`, and parse it afterwards with the other
  grammar (`region in sql`).  The host parser never sees the guest's tokens, which is how precompilers have always
  done it, and it costs nothing for a program that has none.

**5.6  A heading, as in layout.**  Rules defined under a label belong to that grammar:

```
sql:
    statement = "SELECT" ...
```

Natural to a reader; but it changes the shape of a file, and BNF has no headings.

**5.7  A tree of grammars: island and switch** (the user, 2026-11-02).  Grammars form a tree: a root grammar, and
sub-grammars it includes.  A rule of the root can hand the text to a sub-grammar, in one of two ways:

- **Island** (scope and return).  The sub-grammar reads a part, then control comes back to the rule that called it,
  and the host goes on from where the guest stopped.  A stack: enter, leave.  `EXEC SQL ... END-EXEC`, a PICTURE
  string, an interpolation inside a string, a heredoc body.  In lex terms `yy_push_state` / `yy_pop_state`.
- **Switch** (a railway points lever).  The sub-grammar takes over and nothing returns: it reads the rest of the
  input (or until something switches again), and it stays where it was put.  A file's `#!` line or front matter,
  an HTTP header block before a body whose grammar the header names, COBOL's `>>SOURCE FORMAT FIXED`, a `%YAML 1.1`
  directive.  In lex terms `BEGIN(state)`.  A switch is between peers, so no stack grows, and the guest can switch
  again (back to free format, say).

Both can be read as one thing in BNF terms, which would leave the rule syntax alone.  Reference a rule of another
grammar by a qualified name (5.2): `sql.statement`.  That is already an island, because a rule reference returns
to its caller and the sequence goes on.  A switch is the same reference placed last in its sequence, with the
guest's rule being whatever is left of the input:

```
exec-sql      = "EXEC" "SQL" sql.statement "END-EXEC"      ; island: the host continues after it
fixed-section = ">>" "SOURCE" "FORMAT" "FIXED" fixed.rest   ; switch: the rest belongs to fixed
```

What changes is which grammar owns white space, case and tokens: that of the rule being read, so crossing a
qualified reference changes mode, and a rule never has to say so.  The questions this leaves:

- Does the grammar have to say which of the two it means (`sql.statement` against `switch fixed.rest`), or is
  "the reference is last and reads to the end" enough?  Saying so helps the reader and lets the generator refuse a
  switch that is not last, or an island that never ends.
- Where an island ends.  PEG ends it where the guest rule stops; if the guest is greedy past `END-EXEC`, the
  host needs `until` (5.5) or the guest needs a terminator it knows.
- One tree, or two.  An island's tree can be one node of the host's tree (with the guest's nodes under it), or
  text kept for later (5.5).  A switch has a natural answer: the guest's tree is the rest of the host's.
- Mutual switches (free and fixed format referring to each other) need the tree to be a graph of peers, not strictly
  a tree below one root; a switch is the one case where a sub-grammar may name its parent.
- A switch is the case the file-level directives (`whitespace`, `sensitivity`) already cover, one file at a time; it
  extends them to the middle of a file.

## 6. Options for **having** an attribute

**6.1  Parameters, as now.**  The attribute is an argument in parentheses: `entry(K)`, `number(V)`.  A built-in rule
that carries the value of what it matched (`number(V)`, `text(T)`, `column(C)`) gives the binder without a sigil.
This is the logic-grammar (DCG) habit, close to a W-grammar.

```
data-entry(L) := number(L) name *data-clause "." *data-entry(M in L+1..49)
occurs        := "OCCURS" number(N) "TIMES"
```

**6.2  A dotted reference.**  `entry.level`, as members of a record.  Short, and the attribute is named instead
of positional; needs a place to declare which attributes a rule has.

**6.3  A word between rule and attribute.**  `size of picture-text`, `column of item`, `indent of line`: the
attribute reads as the English phrase.  Natural in a comparison (`M > L`), clumsy as a binder.

**6.4  Direction by position.**  One way to tell given from made without a sigil: a domain (`N in 1..17`) means given,
a bare name means made.  Already the practice in the C grammar's `declarator(C in "vars" | "types")`.

Arithmetic (`L+1`) and comparison (`M > L`) already exist in parameters; none of the options changes that.

## 7. Options for **being** a kind of thing

**7.1  `in` for membership.**  `identifier in types`, `identifier not in vars`, replacing `?` and `?!`.  Reads as
set membership.  Overlaps 5.3 (a mode is also "in").

**7.2  `is a`.**  `type-name = identifier is a type`; `variable-name = identifier is a variable`.  The wording the
relation has in speech.  Two words, but unmistakable, and distinct from 5.3.

**7.3  Declaring.**  The matching verb for adding: `typedef = "typedef" specifiers declarator declares type`,
replacing `%bind types += ...`.  With 7.2 it makes a pair a reader can see: what a rule declares, and what a rule
accepts.

**7.4  A kind as a rule.**  Define the kind in the grammar instead of declaring a set: `type ::= name declared by
typedef`.  Everything stays a rule; the declaration is the definition.

**7.5  Scope.**  How long a kind lasts: `block = local "{" *item "}"` (forget what the block declared), or the
reverse, `file` for the whole text.  Replaces `%scope`.

## 8. Three whole sketches, side by side

The same four needs: COBOL's embedded SQL, its PICTURE clause, the level numbers of the data division, and C's typedef.

**A. Least change: directives and parameters.**

```
include "sql.hbnf" prefix "sql-"
exec-sql      = "EXEC" "SQL" sql-text "END-EXEC"      ; island: text until the terminator, parsed later
picture       = "PIC" [ "IS" ] picture-text            ; parsed by the picture grammar when the tree is made
data-entry(L) := number(L) name *data-clause "." *data-entry(M in L+1..49)
type-name     = identifier in types
typedef       = "typedef" specifiers declarator declares types
```

**B. English words.**

```
exec-sql      = "EXEC" "SQL" sql.statement until "END-EXEC"
picture       = "PIC" [ "IS" ] picture-text in picture
data-entry    = level-number name *data-clause "." *data-entry with level > this level
type-name     = identifier is a type
typedef       = "typedef" specifiers declarator declares type
block         = local "{" *item "}"
```

**C. Everything a parameter.**

```
mode ::= "cobol" | "sql" | "picture"
exec-sql      := "EXEC" "SQL" statement("sql") "END-EXEC"
picture       := "PIC" [ "IS" ] text("picture")
data-entry(L) := number(L) name *data-clause "." *data-entry(M in L+1..49)
type-name     := identifier(types)
typedef       := "typedef" specifiers declarator(types)
```

A is the smallest step and uses nothing the reader does not already know.  B reads best and spends the most new words.
C is the most uniform: one mechanism, with the cost that a mode, a value and a kind look alike.

## 9. Questions for review

1. **Decided (the user, 2026-11-02): both.**  An island is a qualified reference `x.rule` (it returns and restores the live rules); a switch is `=> grammar(x)` (sections 18, 19); a qualified reference that comes last is not a switch.  The island's tree is part of the host's (the guest's nodes are children of the open host rule instance).  The original question: Is "a qualified reference, and a switch is one that comes last" enough, or
   should the grammar say which?  And is the island's tree inside the host's, or kept as text (5.5)?  Inline gives one
   error position and one tree; text is cheap and what COBOL tools do.
2. Should `in` mean a mode (5.3) or a kind (7.1)?  They cannot both, unless a mode is a kind of the whole text.
3. Is `is a` / `declares` (7.2, 7.3) too much English for a grammar notation, or the thing that makes it readable?
4. Do attributes need a direction (6.4), or is "given if it has a domain" enough?
5. How is **extent** said (a rule, a scope, a region)?  `local` (7.5) covers the scope; the region needs `until`.
6. Is any of the other kinds of section 3 worth its own form: position, and the earlier text (`%col`, `%as`)?
   They are the other two sigils the grammars still use.
7. Keywords without `%` (section 10): **decided (the user, 2026-11-02): reserved words.**  A keyword cannot name a rule; using one gets an error that says so and suggests another name.  The spellings in the section 10 table stay to be shown before anything is built.
8. Is the active set (section 11) the model?  Named sets only (section 18) is **my recommendation, not yet answered by the user**.  **Decided (the user, 2026-11-02): a missing name is missing, with no look in an enclosing grammar.**  What is left: how two grammars *share* the rules they both include (`free` and `fixed` both include the COBOL rules and differ in `ws`): do they each get a copy of the rules, or do they share one set of definitions and override the differences?  Sharing keeps the generated parser small and is what inheritance means; copying is simpler to build.
9. Facts (section 13): **decided (the user, 2026-11-02): yes** -- a fact is a record of the rule's own attributes, keyed by a name; store at parse time only what the parse needs, the rest stays in the tree for a checking pass.
10. **Decided (the user, 2026-11-02): the switch is spelled `=> grammar(x)`** (a grammar as a parameter value, `grammar(mode)` when matched text names it).  The draft spellings in section 14 (`switch x`, a trailing reference, `->`) are dropped.
11. Section 15: **decided (the user, 2026-11-02): `=>` is the one arrow** for what a match does (value, fact, grammar to read the rest with).  **Decided (the user, 2026-11-02): a grammar is a parameter value, and the consequence form `=> grammar(x)` is the primary form** (not sugar for threading the value).
12. Labels (section 16; the user's own proposal, 2026-11-02, with no yacc clash; **not part of the first slice**): `name:` on a line by itself for the context that follows; per-context directives; dotted nested labels; plain names inside, the dot between.
13. **Decided (the user, 2026-11-02): the first slice is islands plus `=> grammar(x)`** (section 19).  Facts, labels, the `%`-free keywords and the output forms of `=>` come after it.  C's typedef must keep working unchanged throughout.

## 10. Keywords without `%` (the user, 2026-11-02)

`%` is spent on two different things.  `%x41`, `%d65`, `%b0`, `%s"A"`, `%i"a"` are ABNF's own (RFC 5234, RFC
7405), and they stay.  The rest are hbnf's words, written like a directive although they sit inside rules:
`%emit`, `%label`, `%action`, `%token`, `%scan`, `%as`, `%same`, `%num`, `%col`, `%spaces`, `%bind`, `%scope`,
`%where`, `%grammar`.  Quoted text is already a literal (`"..."`, `'...'`), so a bare word in a rule can mean a keyword
the same way `include`, `whitespace`, `dialect` and `prefix` already do at the head of a line.

**The cost: a bare word in a rule is a rule name.**  `a as b` would read as three rules.  Two ways to keep it
unambiguous without a sigil:

- **Reserved words.**  The keywords below cannot name a rule; a grammar that uses one gets a message that says so
  and suggests another name (`emit` is a rule name in this grammar; call it `emitted`).  The list is the whole cost,
  and COBOL, C and SQL all live with one.  Smallest change, and the grammar reads as English.
- **Position.**  A keyword is a keyword only where a rule name could not stand: right after the element it modifies
  (`name as tag`, `type-name where in-scope`), or before a brace (`emit { ... }`).  No reserved list, but a reader
  has to know the positions, and a typo turns a keyword into a rule name that is then undefined.

Suggested words, one idea each, nothing that needs a prefix:

| now | bare | reads as |
|---|---|---|
| `x %as tag` ... `%same tag` | `x as K` ... `$K` | name the text, later say "the same text as `K`" (decided 2026-11-03, below) |
| `%emit ...` | `emit ...` | what the rule writes |
| `%label`, `%action`, `%token` | `label`, `action`, `token` | the same, named by what they are |
| `%num D`, `%spaces K`, `%col` | `number D`, `spaces K`, `column` | a count, an indent, a position |
| `%bind types += decl.name` | `declares types decl.name` (or `adds decl.name to types`) | see 7.3 |
| `%scope` | `scope` | forget what the block declared (7.5) |
| `%where { code }` | `where { code }` | a host-code test |
| `%grammar` | `grammar` | a directive at the head of a line, already bare in spirit |
| `%scan` | `scan` | the scanner action |

Two of these are the same question as the contexts above: `declares`, `scope` and `as`/`same` are the context words,
so settling the notation for contexts (sections 5 to 7) settles most of the `%` list at the same stroke.  What this
page leaves open: reserved words or position; whether `number`/`column` should be shorter (`num`, `col`); and
whether any word is better as punctuation (`@` is out).  The migration is mechanical (a tool rewrites `%word` to
`word` across the corpus and the docs), and under the rule of no compatibility spellings the old form would be
removed at once, not kept.

**Back-references: `as K` and `$K` (the user, 2026-11-03).**  `x as K` captures the text `x` matched under the name `K`; `$K` matches that text again, in the same sequence, as `%as` and `%same` do today (`ABNF.md`, tests/backref, the Mustache grammar).  Named only, never numbered
(`$1`): a number shifts when an alternative is added and a capture inside a repetition or an alternative may not exist on every path, a name does not.  The tag is local to the sequence, so nesting and backtracking work as they do now; a plain `$K` compared the bytes at first (as `%same` did: exact in all four backends, whatever the grammar's
`sensitivity`), while the join `"lit" + $K` follows `sensitivity string %i`.  **Decided later the same day (the user), and built: `$K` keeps the property of what it back-references, see section 26 item 24.**  `$` is free for this because `^` and `$` are not anchors in `r"..."` (section 24); inside a regex string `$K` stays literal text.  It replaces `%as` and `%same` and so removes two more `%` words from the list above; `as` and `same` become reserved words.
The case that asked for it: COBOL's terminators, `add-statement = "ADD" as K ... [ "END-" + $K ]`, where the statement names its keyword once; this makes `scope-end(K)` of section 21 unnecessary for fixed keywords.  Open: whether `"END-" + $K` (a join with a captured text, resolved
at parse time unless the capture is a single fixed literal, which the generator can resolve when the grammar is read) is written that way or `"END-" $K`.  Built 2026-11-03: `x as K` and `$K`; `"END-" + $K` is the form (two elements, `"END-" $K`, would let white space come between them), read as the literal `"END-ADD"` when `K` is kept from one fixed literal in the same sequence, else compared at run time in the sequence that keeps `K`; `%as` and `%same` are refused with the new spelling in the message; `as` is a reserved word (a rule named `as` is refused).

## 11. An active grammar is a set of live rules (the user, 2026-11-02)

A grammar is not one fixed text but a set of rules, and at any point of the input some of them are **live**.  Reading
is always done with the live set; a rule that is not live does not exist for the parser, and a reference to it fails
as a name nobody has.  Switching is changing which rules are live.  That one idea covers most of this page:

| what | as live rules |
|---|---|
| island (5.7) | the guest's rules go live on entry, and the host's set is live again on return: a stack of sets |
| switch (5.7) | the live set is replaced, and nothing is restored |
| dialect (`c79`, `c89`, `c99`, COBOL 85 and 2014) | a set chosen once, usually by a directive or an option |
| a kind (a typedef name, 7.x) | a rule that becomes live when a declaration adds a name: `type-name` holds the names so far |
| reserved words | the set of words that are keywords, which differs by dialect and by mode (SQL's are not COBOL's) |
| a mode's white space and case | part of the set: each grammar brings its own |
| a scope ending (`scope`) | the rules a block made live stop being live |

So "in a context", "is a kind" and "has a dialect" are the same act at different sizes: a rule, a name, or a whole
grammar goes live or stops.  Two consequences for the notation.

- One verb pair is enough, however the names are spelt: something goes **live** (is added to the active set, for a
  stated extent), and something is **live** (the test).  Everything in sections 5 to 7 is a spelling of these two.
- The sets are static and finite, which keeps the cost where it belongs: a grammar that never switches has one set,
  and the generator emits the same parser it does today.  A grammar that switches pays for the table of sets and
  for the stack, and for nothing else.

What to settle: whether a set is named (`sql`, `fixed`) and switched to by name, or built (this rule and these);
whether a rule can be live in several sets (a shared `identifier`), which makes a set an overlay and not a partition;
and what a rule that is not live says when the input would have matched it (the error message is where the user
meets this: "`GOBACK` is not a statement in dialect `cobol85`; it is in `cobol2002`").

## 12. What COBOL would gain (an estimate, 2026-11-02, from the scan of GnuCOBOL's test programs)

| problem | the context | size |
|---|---|---|
| `DECIMAL-POINT IS COMMA` (`-19876,1234`) | an attribute set by SPECIAL-NAMES: another numeric-literal rule is live | about 7 programs refused |
| PICTURE text shares white space with code (a `,` is a separator, `$` began a comment: a real bug) | an island for the picture string with its own tokens | 2 refused; the whole class of bug |
| `Process ...`, `*CONTROL LIST`, `@OPTIONS`, `>>SOURCE FORMAT` | a switch for the rest of the file | about 6 refused, 49 left out of the scan |
| fixed against free format | the same switch, replacing an external converter | the whole corpus |
| reserved words that are legal names (`nested`, `error`, `corr`, `same`, `main`) | the reserved set live only in the procedure division | about 12 refused |
| `OCCURS` on level 01, `REDEFINES` larger, misplaced `VALUE` | the level number as an attribute | about 5 wrongly accepted |
| "not defined", ambiguous, redefined names | a kind (`data-name ? defined`) | about 32 wrongly accepted; better left to a checking pass |

Not helped: `COPY` and `REPLACE` (about 45 refused; they rewrite the token stream, so they are a preprocessor's work),
the XML and JSON statements (about 10; unwritten grammar), and type checks such as an invalid `MOVE`.

For compactness: clauses in any order and each once (SELECT, FD, screen items, SPECIAL-NAMES) are written `*clause` today,
which also accepts a duplicate; "each once" as a kind kept for one rule says it exactly.  One reserved set live per
region replaces the patches in each name position.  Dialects (IBM, Micro Focus, COBOL 85 and 2014) become rule sets
in one grammar, not copies of it.

## 13. A matched rule remembers facts about itself (the user, 2026-11-02)

When a rule matches it can leave facts behind that later rules read: C's typedef is the case hbnf has (a name goes into
a set), and COBOL has many more.  Today the fact is only "this name is in this set"; the proposal is that a fact is
a **record kept under a name**: the rule that matched says what it knows (its attributes, section 6), and a later rule
asks for it.

What COBOL would keep, from the data division and the environment division:

| remembered by | key | facts | read by |
|---|---|---|---|
| a data description entry | the data name | level, parent group, PICTURE category (numeric, alphanumeric, edited), USAGE, OCCURS, REDEFINES, SIGN | class and sign conditions; `MOVE`; subscripts (is it a table?); `INITIALIZE` |
| a level-88 entry | the condition name | the item it belongs to | the abbreviated condition `A > B AND C`: is `C` a condition name or a data name? (the grammar's header says the parser cannot tell; with the fact it can) |
| SPECIAL-NAMES | `DECIMAL-POINT`, currency sign, alphabet and class names, switches | the setting | the numeric literal (section 12); `IF x IS my-class`; `SET sw TO ON` |
| FILE-CONTROL and FD | the file name | organization, access mode, record key | which `READ`, `START`, `REWRITE` forms are valid |
| a paragraph or section | its name | which section it is in | `PERFORM`, `GO TO`, `THRU` (a use before the definition is the norm, so these are checked after, not while parsing) |
| PROGRAM-ID | the program name | `COMMON`, `INITIAL`, nesting | `CALL` of a contained program |

**What is parse-time and what is not.**  A fact belongs in the parser only if it changes what parses: C's typedef
(`T * x;` is a declaration or a product), COBOL's decimal point, a condition name against a data name, a class name.
A fact that only says "this is wrong" (the type of a `MOVE`, an undefined name, a missing file description: nearly all of
the programs `cobc` refuses and the parser accepts) goes into the tree for a checking pass, where forward references
are no problem.  The rule: **store at parse time what the parse needs; keep the rest in the tree.**

**Mechanics that already exist and carry over.**  A fact is added when its rule matches and removed when that match is
given back (a wrong guess puts every set back, as the typedef sets do).  A scope ends what it added (a nested program
sees its parent's facts; a `GLOBAL` item is seen below).  Qualification (`A OF B`) is a lookup by a path of keys.

**Options for writing it**, each only a sketch, all reusing section 6:

- **R1, the attributes stay in parentheses; one word remembers.**
  `data-entry(L) := level(L) name as N [ picture(P) ] [ usage(U) ] "." remembers N(level L, picture P, usage U)`; a read is
  the name with a test: `data-name(usage binary)`.
- **R2, a dotted read.**  `N.level`, `N.usage` after `N` is bound, as the members of a record.
- **R3, a kind is a rule with a body.**  `condition-name = user-word where it has parent` and `data-name = user-word where it has picture`:
  a name is a kind because of a fact, so a kind (7.x) is a fact test and the set is not a separate notion.

R3 is the smallest: it keeps one idea (a rule remembers; a name is of a kind if a fact holds) and makes the earlier
`?` set test a special case with a fact named "declared".

Questions: is a fact always a record of the rule's own attributes, or can a rule remember something it did not match
(the parent group's level)?  Is the key always a name, or can it be a position (the last entry at this level)?  And
how does a fact reach a rule in another grammar (an island sees its host's facts, or not)?

## 14. Qualified names for islands; how to say a switch (the user's preference, 2026-11-02)

Preferred for an island: `include "sql.hbnf" as sql`, and then `sql.statement` where a rule wants it.  The rules inside
`sql.hbnf` are written as ever and refer to each other by their plain names; only the including grammar writes the
prefix.  The included file's own `whitespace`, `sensitivity` and `dialect` apply while one of its rules is read (they are
per file already), so crossing the dot changes the mode.  This is option 5.2 and needs no new word.  **The dot goes in, the caret goes out (the user, 2026-11-03; built):** inside the included file `^.statement` is the rule `statement` of the grammar that includes it, `^.^.statement` the one two levels out, `^.sql.statement` a rule of an island `sql` of the parent; a plain name still means the file's own, and `^.name` is strict (the parent must define it, the root has nothing out of it).

```
include "sql.hbnf" as sql
exec-sql = "EXEC" "SQL" sql.statement "END-EXEC"
```

For a switch, the options, from least to most new:

1. **A qualified reference that comes last.**  `fixed-directive = ">>SOURCE" "FORMAT" "IS" "FIXED" fixed.program`.  No new
   word; the generator sees that nothing follows and the reference reads to the end.
2. **A word.**  `... "FIXED" switch fixed`.  Reads as English; says the intent, so the generator can refuse a `switch` that
   is not last and a grammar that can never come back.  `switch` becomes a reserved word (section 10).
3. **A word with a computed target.**  The grammar to switch to is named by the text just matched, using `as` (section 10):
   `source-format = ">>SOURCE" "FORMAT" "IS" word as mode switch mode`, where the text `FIXED` names the grammar `fixed`.
4. **An arrow.**  `... "FIXED" -> fixed`, the railway picture.  Short, but `=>` is already the idea in step 20 for a rule's
   output form (a word and its number, ALGOL's `begin` and C's `{`), so an arrow would have to be told apart from that.

A heredoc is an island and not a switch: the body is read by the other grammar and control comes back at the
terminator line.  `heredoc = "<<" word as tag  body.text until tag`.  A true switch has no return: `>>SOURCE FORMAT`, the `#!`
line, front matter, `%YAML`.  The guest grammar switches again itself when it must (`cobol-free` reads the directive that
sends it back).

## 15. A grammar as a value; a switch as the consequence of a match (the user, 2026-11-02)

Corrections to section 14: a heredoc is an island (the example there is right that it returns, wrong to have offered it as
the case for `switch`).  A little code-like notation is fine for a rare case.  And a rule can be parameterised, so a grammar can be.

**A grammar is a value, like any parameter.**  `grammar ::= "cobol-free" | "cobol-fixed" | "sql"` is a domain (section 6);
a rule takes one, and a qualified reference may use it: `program(G) = *( G.item )`.  With that alone, switching needs no new
notation: the rule that matches a directive hands the new value on to what follows, by the attribute machinery that
already exists.

```
file(G)        := directive(G, H) file(H)  |  G.item file(G)  |  end
directive(G, H) := ">>SOURCE" "FORMAT" "IS" word as mode   H is grammar(mode)
```

That is exact (no hidden state, and backtracking undoes it for free) and a little verbose, because the value is threaded
through every rule between the directive and the place the file is read.

**The consequence form, as sugar for the same thing.**  Say that a match has a consequence, with `=>`:

```
source-format = ">>SOURCE" "FORMAT" "IS" word as mode  =>  grammar mode
heredoc       = "<<" word as tag  =>  island sql.text until tag          ; an island: the consequence returns
bip-word      = "abandon"  =>  0                                          ; the output form of step 20, same arrow
declaration   = specifiers declarator  =>  declares type                  ; a fact (section 13), same arrow
```

One arrow, one meaning: **what happens because this rule matched.**  The value of a match (`=> 0`), a fact it leaves
(`=> declares ...`), and the grammar the rest is read with (`=> grammar mode`) are all consequences.  A consequence takes effect
only when the whole rule has matched, so it is clear in the text that the switch is *because of* the match and not part of
the pattern, and it is undone with the match when a guess is given back.  This also settles the clash noted in section 14:
the arrow in step 20 and the switch are the same arrow.

**The new grammar sees everything matched before.**  Facts, the texts bound with `as` and the nodes already built belong to the
parse, not to one grammar.  A rule in the grammar switched to can use `same tag`, `N.level`, a kind test (`name in types`) or
a name bound by the host, exactly as a rule of the host could.  What the new grammar does not see is the host's rules: it
reaches them, when it must, by name (`host.item`) as the host reaches it by `sql.statement`.

**Decided 2026-11-02 (the user): `=>` is the one arrow.**  The spellings after it are still to be shown and approved before anything is built.

Open: whether the consequence form is only sugar for passing the value (so the generator can compile it to the threaded
version), or the primary form; and whether a rule may have more than one consequence (`=> declares type, grammar G`).

## 16. Labels: a line that names the context the following rules are defined in (the user, 2026-11-02)

Like Common Lisp's `in-package`, or an assembler's section and label lines: a line holding only a name and a colon says that
every rule after it belongs to that context, until the next such line.  This is 5.6 (a heading) with the model made clear.

```
sql:
statement = "SELECT" columns "FROM" table [ where ]
columns   = column *( "," column )

cobol:
exec-sql  = "EXEC" "SQL" sql.statement "END-EXEC"
```

- Rules before the first label are the root context (named by the file, or `main`).  A label can be returned to, to
  add more rules to it.
- Inside a context, plain names are that context's rules (`columns`); another context's are reached with the dot
  (`sql.statement`), as in Lisp's `package:symbol`.  `include "x.hbnf" as x` stays for rules kept in another file, and gives
  the same names.
- The file-level directives become per context: `whitespace`, `sensitivity`, `dialect` after a label apply to that
  context only, which removes the one-mode-per-file limit without a second file.  A mode is then just the directives
  of the context being read.
- Nested contexts take a dotted label (`sql.select:`), which makes the tree of grammars of section 5.7 visible in the text.
- A switch names a context by its label: `=> grammar(sql)`; `grammar` takes a label as its value (section 15).

Labels are an hbnf notation; the other dialects keep their own forms (the user, 2026-11-02: there is no yacc clash, yacc is not hbnf).

Questions: do contexts see each other's plain names (Lisp's `use-package`) or only by the dot?  Does a label start a new
context or reopen one with the same name?  And should a context be allowed to inherit another's rules (a dialect that is
`c99` plus changes), which is what a rule set (section 11) with an overlay would give?

## 17. Prior art (checked against sources 2026-11-02; what a source did not say is marked)

| system | the piece it has | source and status |
|---|---|---|
| OMeta (Warth, Piumarta) | foreign rule invocation: a grammar "lends" its input stream to another grammar to use one of its rules, written as the rule `foreign` with the foreign parser and the rule name, `foreign(JSParser, 'srcElem')`; single inheritance besides; the point is to combine grammars without name clashes | confirmed from the text of Warth's 2009 dissertation, section 2.3.4 (the example `OMetaJSParser` that is the union of OMeta and JavaScript): <https://www.cs.ucla.edu/~todd/theses/warth_dissertation.pdf>, <https://en.wikipedia.org/wiki/OMeta>.  The section says nothing about memoization or left recursion in foreign calls |
| Ragel | `fcall` pushes a return target and jumps, `fret` returns to it (an island); `fgoto` jumps with no return (a switch); `fcall` needs a declared call stack | confirmed: the Ragel man page: <https://www.mankier.com/1/ragel> |
| Raku grammars | a grammar is a class, inherits with `is`, composes with roles; a "slang" changes the language for a lexical scope by mixing a grammar role and an actions role into the current sublanguage (`$*LANG`, `define_slang`) | confirmed: the Raku slang documentation <https://docs.raku.org/language/slangs>, roast test `S05-grammar/inheritance.t`; slangs act when the program is compiled, not when it runs (an earlier draft said run time: wrong) |
| TextMate grammars | `begin`/`end` rules with their own nested `patterns`; `include` names another language's scope (`source.php`), `$self` the grammar itself; `contentName` gives the inner text its scope | confirmed: the TextMate manual <https://macromates.com/manual/en/language_grammars> |
| Colm (Thurston) | each `lex` block is a **lexical region**: when the parser asks for a token the scanner uses only the regions that hold tokens the parser can take at that point; a `context` block holds data (and `lex` blocks) that reduction actions write and token actions read to decide which tokens the parser gets (the typedef case); the parser backtracks and Colm undoes what actions did to that data | confirmed from Colm's own manual, `doc/colm/3_01_lex.adoc` ("Lexical regions") and `3_04_undo.adoc` ("Context-dependent parsing"): <https://github.com/adrian-thurston/colm/tree/master/doc/colm>.  Corroborated by a Hacker News thread in which the author (user `thurston`) says Colm "keeps only one global state, but stores instructions for programmatically reverting the state": <https://news.ycombinator.com/item?id=2560288>.  An earlier draft of this table discounted the claim because it came from a comment, and was wrong to: the manual and the author's own comment support it.  Not found in the manual: the term "island grammar" |
| Copper (with Silver) | context-aware scanning: the parser passes the scanner the set of terminals valid in its current state and the scanner returns only those; an analysis that the scanner cannot return two tokens for one input; a modular determinism analysis that independently written extension grammars compose with a host | confirmed: Van Wyk and Schwerdfeger, GPCE 2007 <https://galois.com/wp-content/uploads/2023/06/gpce.pdf>; Kaminski and Van Wyk 2013 <https://www-users.cse.umn.edu/~kami0054/papers/parsingatsle2013.pdf>; Silver is a separate attribute grammar system, Copper its parser and scanner (<https://melt.cs.umn.edu/silver/tutorial/6_what_next/>) |
| SDF with SGLR, MetaBorg | syntaxes defined and combined in SDF, parsed scannerless-GLR; embeddings of a Swing UI language, regular expressions and Java itself in Java | confirmed: Bravenboer and Visser, OOPSLA 2004 <https://eelcovisser.org/publications/2004/BravenboerV04.pdf>.  Spoofax pairs SDF3 (declarative syntax, generalized scannerless parsing, full context-free grammars) with Stratego and NaBL2: <https://spoofax.readthedocs.io/en/latest/source/langdev/meta/lang/sdf3/introduction.html> |
| ANTLR 4 | lexer modes: `mode(x)` switches, `pushMode(x)` and `popMode` keep a stack; commands go at the end of a lexer rule's outermost alternative | confirmed: <https://github.com/antlr/antlr4/blob/master/doc/lexer-rules.md>.  The page says "Modes are not allowed within combined grammars, just lexer grammars", "the lexer can only return tokens matched by rules from the current mode", and that popping the bottom of the mode stack is an exception.  It does not say whether a parser can switch modes: that remains my inference |
| flex | start conditions, inclusive (`%s`) and exclusive (`%x`); `BEGIN` switches; `yy_push_state` and `yy_pop_state` (with `%option stack`) | confirmed: the flex manual <https://westes.github.io/flex/manual/Start-Conditions.html> |
| Common Lisp readtables | `set-macro-character` changes the reader's behaviour for a character by modifying a readtable (by default the current one) | confirmed: the HyperSpec <https://www.lispworks.com/documentation/HyperSpec/Body/f_set_ma.htm>.  `in-package` is confirmed in the HyperSpec as setting `*package*`, also at compile time when top-level (<https://www.lispworks.com/documentation/HyperSpec/Body/m_in_pkg.htm>); that the change lasts to the end of the file is not stated on that page |
| Racket | `#lang reader <module>` names a module whose `read` and `read-syntax` produce the module from the rest of the file; readtables extend the reader (`make-readtable`) | confirmed: <https://docs.racket-lang.org/guide/hash-lang_reader.html>, <https://docs.racket-lang.org/guide/hash-reader.html> |
| tree-sitter injections | `injections.scm`: `@injection.content` re-parsed in another language, named by `@injection.language` or `injection.language`; `injection.combined` parses all matches as one document; child text excluded unless `injection.include-children`; a heredoc tagged `BASH` is parsed as Bash | confirmed: <https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html>; `ts_parser_set_included_ranges` is confirmed in `api.h` (parse only a portion of a document, several disjoint ranges allowed, ordered and not overlapping; otherwise the call fails and assigns nothing): <https://github.com/tree-sitter/tree-sitter/blob/master/lib/include/tree_sitter/api.h> |

What matches this page: the call into another grammar and inheritance (OMeta, Raku), call-and-return against jump (Ragel), the
parser's state choosing what the scanner may return (Copper, Colm's lexical regions), begin/end islands (TextMate), a stack
of modes (ANTLR, flex), an island parsed apart and joined by queries (tree-sitter).  Colm is the nearest on facts: its `context`
blocks hold what actions record during the parse (its typedef example), and are undone on backtracking, as section 13
wants; they are written in Colm's programming language, not in the grammar notation.  What none of the systems read was seen
to have, in one declarative notation: a switch that is the consequence of a match (`=>`), the new grammar seeing what matched
before as facts and bound texts, and the same notation also saying that a name is a kind and that a rule has attributes.  That
is a statement about the systems read here, not a survey of all of them.


## 18. Three points settled or sharpened (the user, 2026-11-02)

**Spelling.**  A switch is written `=> grammar(sql)`, a call with the grammar as its argument, as a rule is parameterised
(`=> grammar(mode)` when the text just matched names it).  It replaces the draft spellings `=> grammar sql` and `switch sql`.

**A qualified reference that comes last is not a switch.**  A reference to `sql.statement` is an island: when the guest rule
stops matching, control returns to the host, which carries on with whatever follows the reference, and if nothing follows in that
rule, with the rule that called it.  That is the ordinary meaning of a rule reference in a PEG, and it cannot also mean "keep
the other grammar".  So a switch has to be said.

**What a switch does (corrected by the user, 2026-11-02): it changes the live rules, and abandons nothing.**  The rules the host had
open stay open.  From the switch on, the names the parse looks up resolve in the new grammar, as a derived grammar overrides a
base one, and what the new grammar matches is written into the nodes the host had opened and identified: the guest adds its
content at the points the host left open, and the host's own pending parts (a closing `}`, the next statement of a list) go on
matching under the new set.  There is no start rule to run to the end of the input and no fall back, since the host's
continuation is what keeps running; a pending host rule that names something the new grammar does not have is an error that says
so ("`item` is not live in `fixed`", the message of section 11), and a mismatch is an error at its position like any other.  An
island differs only in extent: it sets the live rules for one reference and restores them when it ends; a switch sets them until the
next switch.

```
source-format = ">>SOURCE" "FORMAT" "IS" word as mode  =>  grammar(mode)     ; only ws and the token rules differ: the rest of COBOL carries on
exec-sql      = "EXEC" "SQL" sql.statement "END-EXEC"                          ; an island: the live rules are restored here
```

**Decided (the user, 2026-11-02): the points the host opened are the host's open rule instances, and nothing extra is written.**  The
guest's nodes become children of whichever host rule instance is open when they are matched.  The host does not name holes and
cannot limit what a guest adds beyond what the live rules allow.

**Named sets against built sets.**  A *named* set is a grammar or context that the file defines once and refers to by its label or
include name: `sql`, `fixed`, `cobol-free`.  A *built* set would be assembled during the parse from parts: `c99` plus the
rules a declaration has made live, or a union of two grammars.  Two things already give "built" without a second concept:
inheritance between named sets (`c99` is `c89` and its changes, section 16's last question), and facts that make single rules live
(a typedef makes `type-name` match, section 13).  The recommendation is to have **named sets only**: a context is a label,
`grammar(x)` and `x.rule` name it, a dialect is one that inherits from another, and the dynamic part is facts.  This removes the
"sets named or built" half of question 8.


## 19. The first slice: islands and `=> grammar(x)` (approved 2026-11-02; built as the two status sections after it say)

Exactly what was to be implemented, and nothing more.  What differs in the built form is in the two status sections below.

**Syntax.**  (Built later: `^.name` in the included file is a rule of the including grammar, the way out of an island, as the dot is the way in.)

```
include "sql.hbnf" as sql              ; a file's rules, reached as sql.name; its own whitespace/sensitivity/dialect directives apply to them
exec-sql = "EXEC" "SQL" sql.statement "END-EXEC"                       ; island
mode-directive = ">>" "MODE" word as m  =>  grammar(m)                  ; switch, the grammar named by the matched text
fixed-directive = ">>" "FIXED"  =>  grammar(fixed)                     ; switch to a named grammar
```

- `include "file" as name`: the file is a grammar named `name`; without `as` it is the file's rules merged into the including one, as `include` is today.
- `name.rule`: a rule of the grammar `name`.  **The dot is never part of a rule name (the user, 2026-11-02): it always means scope or context**, `scope.rule`, and scopes nest (`a.b.rule`).  The one way to have a dot or a space in a name is the angle-bracket form: everything between `<` and `>`, the brackets included, is one bareword, so `<my . bare . word>` is a single rule name and `<my . bare . word>.foo` is the rule `foo` inside the scope named `<my . bare . word>`.  (The dotted path in `%bind types += decl.name` is the same idea: `name` inside `decl`.)
- `=> grammar(x)` ends a rule, after its pattern: `x` is a grammar name, or a name bound earlier in the same rule by `as` (`word as m`; it was `%as m` when this was written).  It is the only form of `=>` in this slice (the output forms come later).
- The `%` words stay as they are in this slice; Q7 is not touched.

**Meaning.**

1. Each included grammar has its own rule table, directives and tokens.  The including grammar's table is the root.
2. At every point of the parse there is a *current grammar*.  Looking up a plain name looks in that grammar's table only: its own rules, the rules of the files it includes, and the built-in names.  **A missing name is missing** (the user, 2026-11-02): it is an error at generation ("rule `item` is not defined in grammar `fixed`; include the file that defines it"), never a look in the grammar that included this one.  A grammar that is to take over from another in the middle of a parse, as `fixed` does from `free`, includes the rules it shares and overrides the ones that differ.
3. `x.rule` is an island: the current grammar becomes `x` for the length of that rule reference, and is restored when it succeeds or fails.
4. `=> grammar(x)` is a switch: when the rule that carries it has matched, the current grammar becomes `x` and stays so until another switch.  The host's open rule instances stay open and go on under `x`; the nodes `x` matches are children of whichever instance is open.  Nothing is abandoned and nothing falls back.
5. The current grammar is part of the parse state and is put back when a guess is given back, as the typedef sets are.  A switch inside a speculative branch is undone with the branch.
6. A grammar that uses neither costs nothing: no tables, no extra state, the same generated parser as today.

**Generator.**  The C backend first (the current grammar as one integer in the parse state; the rules that exist in more than one grammar dispatched through it; the scanner chosen per grammar for `ws` and tokens), then Rust, Zig and Ada.  The tree-sitter backend refuses a grammar that uses a switch, with a message, until it can write what tree-sitter needs (the user's suggestion, 2026-11-02): `grammar.js` only runs when the grammar is generated, so a rule cannot test the live context while parsing, but an **external scanner** can.  The backend would generate one (C, with the mode in its serialized state): a rule of a context starts with a zero-width external token that the scanner returns only when the live context is the rule's declared one (`valid_symbols` says which tokens the table allows), and a switch ends with a token that changes the mode.  That is implementation, not a workaround, and comes after the four backends.  Islands that share the including grammar's white space and case settings merge as prefixed rules; others wait for the same scanner.

**Tests.**  A small calculator with a `>>FIXED` / `>>FREE` switch that changes only `ws`, and an `EXEC SQL` island inside a host, through all four backends; then COBOL's `>>SOURCE FORMAT` and a COBOL embedded-SQL toy.  C's typedef grammar must pass unchanged.

**Left for later.**  Facts and kinds (section 13), labels (section 16), inheritance between grammars, the output and fact forms of `=>`, the `%`-free keywords (section 10).

Questions before building: **answered 2026-11-02** -- `include ... as` is the place for the scope name, and `.` is the scope operator, never part of a name.  What remains is the go-ahead to build the slice as written here.

**Order of work (the user, 2026-11-02).**  Stage 1: islands (`include ... as`, `x.rule`, the dot as scope), all backends.  Stage 2: `=> grammar(x)`, the C backend first, then Rust, Zig and Ada; tree-sitter refuses a switch until it can write an external scanner.  Then use both to **condense the C and COBOL grammars** (the sigils and repeated rules that contexts replace: the typedef context, COBOL's per-region reserved words, fixed and free format as grammars, the decimal-point setting).

## Stage 1 status (islands only, built 2026-11-02)

Built: `include "file" as x`, `x.rule` and `a.b.rule`, the rule that a dot is never part of a name (a definition with a dot is an
error; `<...>` is the way to have one; `<...>.rule` is not read), scoped files read once per scope.  A scoped rule is named
`x--rule` inside the generator (a legal identifier in every backend; Ada folds `--` to one `_`), and `Spelled` gives `x.rule` for a
message.  Not built: `=> grammar(x)` (stage 2).

Differs from the text above: (1) a plain name in a scoped file is resolved only against that file's own closure (its rules, the files
it includes into the same scope, the built-in names); there is no fallback to the including grammar (the correction of the same day),
and a name found nowhere is an error saying so.  (2) Section 19 meaning 1 says each grammar has its own directives, tokens and tables;
the generated parsers have one white-space rule, so a scope either shares the including grammar's `ws` or says `whitespace none`, and a
scope that skips with a rule of its own is refused until a later stage gives each grammar its own scanner.  `sensitivity` and `whitespace
none` are per file already and work as written.

## 20. What the C and COBOL grammars would gain (measured 2026-11-02, before stage 2)

Measured on the grammars as they stand:

| grammar | lines | characters | rules |
|---|---:|---:|---:|
| `corpus/c/c11.hbnf` | 145 | 10,442 | 82 |
| `corpus/cobol/cobol.hbnf` | 361 | 31,859 | 186 |
| `corpus/cobol/cobol-words.hbnf` | 48 | 2,897 | 18 |

**C** is already small, and its context machinery is 8 words (`%scope` four times, `%bind` once, `%start` once, `context` twice, `?` and
`?!`).  Contexts as designed here add no capability it lacks (the typedef case works), so the saving is the `%` sigils and little else,
well under 1%.  What stays to be shown by C is that the new notation reads at least as well for the same four lines of context.

**COBOL** is where the gain is, and it is not mostly in the machinery the first slice builds.  Counted in `cobol.hbnf`:

- **Noise words: 260 optional words, 2.8 KB, 9% of the characters** (`[ "IS" ]` alone 88 times; `WITH` 21, `ON` 15, `KEY` 9, `TO` 8, `ARE` 6, `AT` 6, `IN`
  6).  The standard allows each in particular places, so the grammar spells it there.  A context with its own skip rule would say it once: in the
  data division, white space may also be `IS`, `ARE`, `TIMES`; in a `SELECT`, `IS`, `TO`, `WITH`.  This accepts a noise word in more places than
  the standard allows, inside a region that already is the place for clauses; the scan against `cobc` would show whether that over-accepts in
  practice.  It needs **labelled contexts with their own `whitespace`** (section 16), which the first slice does not include, so the order of
  work puts them next.
- **Name patches**: `user-word`, `not-a-name`, `no-letter`, `function-name`, `program-name` and the `XML`/`JSON`/`ABSENT`/`EQUALS` entries are the places where "reserved here, a name there"
  was patched by hand (five rules and a list).  A reserved set live per region replaces them.
- **Capabilities, at no growth**: the decimal point (one fact, one numeric rule), fixed format (`fixed` as a second grammar, `=> grammar(fixed)`),
  the PICTURE string (an island, which would have prevented the `$` bug), embedded SQL and CICS (islands), clauses each once.

What contexts will not shrink: the statements themselves.  `statements`, the exception, size-error and invalid-key phrases are already shared
rules (27, 7, 6, 6 uses).  Any further cut there is factoring, not contexts.

So the honest target: C about the same; COBOL around a tenth fewer characters from the noise words and some rules from the name patches, with the
decimal comma, fixed format and SQL as additions that cost a few lines each.

## 21. Factoring, measured (2026-11-02): what the current notation allows, and what it asks for

COBOL, factored by hand with today's notation: `cobol.hbnf` went from 32,202 to 30,732 characters (4.6%), and the parser's verdict and
error position are identical on all 1,572 programs of the scan.  What paid: the optional words as rules (`is`, `with`, `on`, `key`, `to`, `at`,
`are`, `number`, `by`: 2.2%), `thru`, `procedure-range`, `control-name`, `item-clause` (1%), and two real duplications in the
screen section (`screen-clause` repeated `screen-attribute`'s keywords, and `screen-phrase` had an alternative the nullable `with` already covered:
1.6%).  What did not pay: tiny rules (`corr`, `returning`, `giving`, `sort-key`, `sign-word`): each costs about what it saves, and the file stayed the same size.

So the notation is the limit, not the effort.  What is left is repetition that no rule can express, because the repeated part is *inside* a literal or
is a pattern, not a value:

1. **The five phrase families** (`size-error`, `on-exception`, `invalid-key`, `at end`, `end-of-page`) have one shape: `( on W statements ) [ "NOT" on W statements ] | "NOT" on W statements`,
   with W a different word each time.  A rule that takes a *pattern* (`phrases("SIZE" "ERROR")`) is one rule and five calls.
2. **Scope terminators**: about thirty `[ "END-x" ]`, the word spelled again in the terminator.  A literal built from a parameter (`end("IF")` giving `"END-IF"`).
   Tested today: a rule with a word-list parameter takes numbers or fixed words as values, not text spliced into a literal.
3. **Singular and plural**: `"RECORD" is | "RECORDS" are`, `"LINE" | "LINES"`, `"SECOND" | "SECONDS"`, `COLUMN`, `AREA`, `LIMIT`, `CONTROL`: a word and its plural.
4. **C's GNU spellings**: 32 alternatives, 490 characters (5% of C's rules): `"const" | "__const"`, `"restrict" | "__restrict__" | "__restrict"`, `"asm" | "__asm" | "__asm__"`.  A literal
   that also matches the same word with leading or trailing double underscores.

These are not contexts; they are notation questions, in the spirit of the standing aim (the smallest total ruleset).  Sketches, for the user to choose among or reject:

```
phrases(W) := ( on W statements ) [ "NOT" on W statements ] | "NOT" on W statements      ; a rule parameterised by a pattern
size-error-phrases = phrases("SIZE" "ERROR")
end(K) := [ "END-" K ]                                                                   ; a parameter spliced into a literal
if-statement = "IF" condition ... end("IF")
"RECORD"s                                                                                ; a word and its plural (a suffix modifier)
%u"const"                                                                                ; or "const"_ : with or without the double underscores
```

Nothing here is built.  Which, if any, are wanted, and in what spelling, is the question.

**Built (09b966c, used 2026-11-03).**  A rule may take a pattern: `phrases(W) := W statements [ "NOT" W statements ] | "NOT" W statements [ W statements ]`, called `phrases(on "SIZE" "ERROR")`; `+` joins literals at read time (`"END-" + K`), an argument that is one quoted word needs no list of the words it may take.
COBOL uses both: the six ON ... / NOT ON ... phrase rules are `phrases(W)` (d51af0b: 534 characters and 8 rules fewer, and the phrase pair may come in either order for all six), and the twenty-one terminators are `scope-end(K) := [ "END-" + K ]` (a7c3f37: one rule more, 35 symbols fewer by the repository's count, 93 characters more).
**The measure is tokens, rules and concepts, not characters (the user, 2026-11-03):** a family of look-alike rules is one concept to state once, and the cost of a new rule is weighed against that.

## 22. What a switch target may override (decided by the coordinator 2026-11-02 after the stage 2 agent found the problem; the user can redirect)

Every backend emits a typed tree: a host rule's field holds a value of the exact type of the rule it names.  A dialect's version of a *phrase*
rule would have its own node type and could not be stored there.  So in stage 2 a switch target (a dialect, section 19's resolution rule) may override
**only the white-space rule and token (text) rules**, whose value is just the matched text and so has the same type either way: this is
what fixed against free format (`ws`), a decimal comma (the numeric-literal token) and per-region reserved words (the exception token) need.  Overriding a
phrase rule in a switch target is **refused** at generation, with a message that says why.  Structural overrides wait for a decision on typing
(the same shape generated into the host's type; text-only; or a dynamic tree, which would change every grammar's output).
**No optimization is given up by switching** (the user, 2026-11-02): an optimization goes away only if it becomes invalid for some other reason.  A fast path that bakes in the white-space rule or an overridden token is generated per grammar and chosen by the current grammar where it is entered; one that touches neither keeps its single copy.  Grammars that do not switch are unchanged, byte for byte.

**Layouts (the user, 2026-11-02).**  The restriction above is for the typed tree (`layout ast`, the default).  Under `layout tape`, where a node is a rule
id and offsets with no type of its own, a switch target may override any rule, phrase rules included.  Built after the `ast` case.

**Phrase overrides in the typed tree (the user, 2026-11-02): by variants.**  Section 22's refusal of a phrase-rule override under `layout ast` is temporary.  The plan: a reference
to an overridden phrase rule N holds a choice of N's node or the dialect's `x--N` node, which hbnf already generates for a choice whose alternatives are
different record types; the generator synthesizes the choice and rewrites the references.  Only a grammar with such an override gets the variant types.  Order of work: the token and
white-space case in C; then phrase overrides in `ast`; then the tape case; then Rust, Zig and Ada.

## Stage 2 status (white-space dialects, built 2026-11-02)

Built: `=> grammar(x)` and `=> grammar(tag)` (the tag bound by `x as tag`) at the end of an alternative, through the C, Rust, Zig and
Ada backends.  A switch is an event at the position where its alternative ended; the current grammar is the last event in force, and
going back before an event undoes it (every restore of the position in the generated parse functions goes through one macro or method
for a parser that switches, so a switch in a guess that is given back is undone).  The caches keyed by position (white space, the word
read) are forgotten when the grammar changes.  What follows the current grammar is `skip_ws`: one dispatch on the grammar, each
grammar having its own scanner.  A parser without a switch is generated exactly as before.

Differs from the text above: (1) a grammar switched to replaces white space only so far.  A rule it defines under the name of one the
including grammar has is refused (token rules are the next step, phrase rules need a typed variant), and so is a reference from the
including grammar to one of its rules when its white space differs from the including grammar's.  (2) The switch is written only in
the including grammar's own file.  (3) An alternative that can match no text may not switch.  (4) The host's rules keep their own
choice of whether to skip white space; a switch changes which rule skips, not whether a rule does.  (5) The tree-sitter backend refuses a
grammar that switches.  The current grammar is a function of the journal of switches and not of the position alone: a position-only
rule reads a stale switch left by an abandoned guess when the next guess passes the same place without asking the grammar.

## 23. Regular expressions and insensitive strings as string prefixes (the user, 2026-11-02; decided and built, 8328962)

The idea, as the user clarified it: prefixes on a string, as Python has them, not a separate regex notation.

- `r"..."` (first written `re"..."`; the user chose `r`): a regular expression, written raw (no escape processing, as Python's `r""`): `r"[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?"`.
- `i"..."`: a case-insensitive literal, which is `%i"..."` (RFC 7405) without the percent sign.  The prefixes combine as flags (`ir"..."` is an insensitive regex).
  Open: whether `%i"..."` stays in the ABNF dialect only, where RFC 7405 requires it, or in all of them.

Meaning: a read-time desugaring into the existing fragments (alternation, repetition, character classes), so no backend changes and no existing grammar's output changes.  The
meaning is hbnf's: repetition is greedy and does not give back (Python's possessive quantifiers), `|` is ordered, there are no lookarounds and no anchors (`!` and `&` already
say lookahead); classes, groups, `* + ? {m,n}` and `\d \w \s` work.  A pattern that needs backtracking to mean what a regex engine would give it is refused, with a message that says so.
Allowed in rules of characters (tokens); in a phrase rule a literal is a keyword matched as a whole word, which a regex is not, so a bare regex there is refused and a named
rule of characters (`plural = re"RECORDS?"`) is the way.
Effect: the token sections shrink (COBOL's numeric literal about 90 characters to about 40, the TOML dates, the YAML scalars), and the plural and underscore-affix words of section 21 become
one short regex each.  An estimate, about 5% of COBOL; not measured.

**Numbers in C syntax (the user, 2026-11-02; decided and built, 8328962).**  In hbnf's own notation the numeric terminals take C's number syntax in place of ABNF's `%x`, `%d`, `%b`:
`0x41` (hex), `0b1000001` (binary), `65` (decimal) are the code point; a range is `0x41..0x5A` (the `..` of `1..17` that parameters already use); a run of code points is the numbers one after another
(`0x41 0x42`).  A leading-zero decimal (`0101`) is refused, with a message, since C reads it as octal and nobody writes that on purpose.  A decimal number glued to the element after it
(`3DIGIT`) is a repetition count as it always was; a number is a code point when a space, `|`, `)`, `]` or `..` follows it.  The `%x`, `%d`, `%b` forms stay in the ABNF dialect, where RFC 5234 has them,
exactly as `%i"..."` does (this section's `i"..."`).  The character literal `'A'` with C escapes (`'\x41'`, `'\n'`, `'é'`) and the range `'A'..'Z'` stay as the other spelling of a code point.
Effect: fewer sigils and a syntax a C programmer reads without a manual; not shorter (a single `0x41` is the length of `%x41`, a range `0x41..0x5A` is longer than `%x41-5A`).  The corpus has 430 such terminals:
321 single `%x`, 95 `%x` ranges, 14 decimal or binary.

**Decided (the user, 2026-11-02): build all three; the `%` forms stay in the ABNF dialect only; the regex prefix is `r`, not `re`.**  In hbnf's own notation the spellings are `i"..."` (insensitive), `r"..."` (a raw regular expression),
and C numbers (`0x41`, `0b1000001`, `65`, `0x41..0x5A`).  The reason is taste: `%` looks noisy.  The `%x`, `%d`, `%b`, `%i`, `%s` forms are refused in an hbnf-dialect file with a message that gives the new spelling, and a tool rewrites the
repository's grammars (the generated output of each must be byte-identical before and after).  `s"..."` (sensitive) exists beside `i"..."`, for a file whose `sensitivity string` is insensitive.  The flags combine as `ir"..."`.

**Built (8328962, 2026-11-03).**  `i"..."`, `s"..."`, `r"..."` (flags in either order: `ir"..."`), C numbers (`0x41`, `0b...`, `65`, `lo..hi`), the `%` forms refused in an hbnf-dialect file with the new spelling in the message and kept in
`dialect abnf`, `tools/hbnf_modernize.py` for the rewrite; a regex is allowed in rules of characters only, greedy and with no giveback, `.` is any character but a line feed, and lookarounds, `\b`, `\A`, `\Z` and (decided 2026-11-03) `^` and `$` are refused;
`bol` and `eol` (section 24) are written beside the regex.  The repository's grammars read the same generated output as before.  COBOL's token file in the new notation is 3,244 characters, it was 3,544, with the same verdict on both corpora (62c7a66).
**Known defect (found 2026-11-03).**  In the full COBOL grammar, `exponent = ir"E"` (and the whole numeric literal as one regex) stops `1.23E0` being read, while small grammars with the same rules pass; being fixed, a regression test with it.  `exponent` stays `0x45 | 0x65` until then,
and `picletter` stays code points because the white-space scanner reaches it.

## 24. Line starts and ends, the column of a rule, and `where (col = x)` (the user, 2026-11-02 and 2026-11-03; `bol`/`eol` decided and being built, `col` a proposal)

The user: a rule should be able to access its column value, written something like `*ws "foo" where (col = x)`.  What fixed-format COBOL needs, and what a prototype of it showed
was missing: the sequence area (columns 0 to 5), the indicator (6), the text (7 to 71) and the ignored area (72 on) are defined by column, and a rule of characters such as `ws` has no way to
ask.  A line-start trick (`LF` then six characters) cannot reach the first line of the file, which has no line end before it, nor the area after column 72.

- `col` is a built-in value readable in every rule, including a rule of characters; it is 0-based, as every index here is, and counts code points from the last line end.
- `element where (condition)` is a postfix on the element before it, tested at the position where that element starts; a group carries it for several elements.  So `*ws "foo" where (col = x)`
  means: skip white space, then `foo`, provided `foo` starts in column x.
- The condition is a comparison (`= != < <= > >=`) of `col`, numbers, the parameters of the rule and the numbers `%col j` bound, joined with `and`, `or`, `not`.  No host code, so it works in all four backends.
  `where` is a reserved word of the keyword change (CONTEXTS.md section 10) and covers the simple cases of `%where { code }`.
- Implementation notes for whoever builds it: in a scanner the column is the distance back to the last line end, or carried by the loop; a rule whose conditions mention `col` cannot be a pure function of the text from the
  position on, so the analyses that treat scanners as such (first-byte sets, ladders) must see the condition as a lookahead-like test.

Fixed format then reads, with no line-start trick and with the first line working:

```
ws = SP | HTAB | CR | LF | "," | ";" | "*>" *~LF | ">>" *~LF
   | ~LF where (col < 6)                    ; the sequence area
   | ( "*" | "/" | 0x44 | 0x64 ) *~LF where (col = 6)   ; a comment line, a debugging line
   | "-" where (col = 6)                    ; a continuation
   | ~LF where (col >= 72)                  ; the area after column 72
```

**Anchors in `r"..."` (the user, 2026-11-02; superseded 2026-11-03: see `bol` and `eol` below, no `^` or `$`).**  In a regular-expression string `^` is the first column of a line and `$` the last (the position just before a line end, or the end of
the input): `r"^[0-9]{6}"` is six digits starting a line.  They are what `where (col = 0)` and "a line end follows" say, as lookahead-like tests that consume nothing, so they follow section 24's `col`.  `\b`, `\A` and `\Z` stay refused.

**`30WS` reaches column 30 (the user, 2026-11-02).**  Open, two readings: (1) a count of white-space units from a line's start, where a tab is the number of columns it advances (to the next multiple of 8), so `30WS` from column 0
ends in column 30 whatever tabs the line holds; (2) a target: white space up to column 30 from wherever the parser is.  Reading 1 is the existing repetition `30WS` once `WS` counts columns and not characters; reading 2 is new.
Fixed-format lines then read: `^ 6*6~LF` is the sequence area and `7WS` the margin.

**`bol` and `eol` (the user, 2026-11-03).**  The beginning and the end of a line, as zero-width built-in rules of the grammar, named like `ALPHA` and `DIGIT`, not reserved words: usable in a rule of characters, a phrase rule and `ws`, consuming nothing.  `bol`
holds when the position is the start of the input or follows a line feed; `eol` when a line feed, a carriage return or the end of the input comes next.  Inside `r"..."` there are no `^` and `$`: with `bol` and `eol` as rules they are not needed (one way, not two); the
refusal of an anchor in a regex points to the two rules.  `bol` needs a look at the byte before the position (no element does that now; lookbehind is missing), a primitive in the scanners and the phrase code of the four backends; `eol` is a lookahead.  They cover
most of what fixed format and other line-oriented formats ask of `col`; `where (col = n)` stays for an exact column.  The first lines of a fixed-format file then read `bol` where a trick with the line feed fails on the first line.  Asked of the literals agent, 2026-11-03.


## 25. Rewrite rules: a grammar that writes its output (the user, 2026-11-03; a proposal, from a worked example, nothing built)

The user: give the most compact and readable grammar for the Markdown Claude Code writes, into a tape or tree, with a C back end that turns it into Typst, or
use rewrite rules if they are advanced enough; "rewrite rules will really want backreferences within the rule, and also `up` references to things captured by the
parent rules the rule is reached from".

**Built and measured first (`corpus/markdown`).**  The grammar `markdown.hbnf` is 44 rules, 439 symbols; it makes a tape (`--layout=tape`), and `typst.c` walks it: 13 functions, 202 lines, 1,437 symbols,
three times the grammar.  The tape has the rule names as tags, so the walker reads as the grammar does (`case T_heading:`).  `tests/markdown.sh` checks five documents against their Typst.

**The same conversion as rewrite rules** (a sketch, not accepted by any reader; measured by `bench/count.py` as 42 rules, 544 symbols, 3,164 characters for grammar and output together):

```
hidden SP WSP LF CR DQUOTE nl blank starter cell-end ticks rest dash dashes title

document = *blank *( block(0) *blank )                                   => trim($block)
block(N in 0..) := heading | fence(N) | rule | quote(N) | table(N) | list(N) | paragraph(N)

heading   = hashes 1*SP 1*inline *WSP nl                                 => rep("=", len($hashes)) " " $inline "\n\n"
hashes    = 1*6'#'
rule      = dashes *WSP nl                                               => "#line(length: 100%)\n\n"
dashes    = 3*'-' | 3*'*' | 3*'_'
paragraph(N in 0..) := line *( LF %spaces N *SP !starter line ) nl       => join($line, "\n") "\n\n"
quote(N in 0..)     := qline *( %spaces N qline )                        => "#quote(block: true)[\n" indent(2, join($line, "\n")) "\n]\n\n"
qline     = '>' *SP [ line ] nl
line      = 1*inline *WSP                                                => trim($inline)
starter   = r"[#>|]|`{3}|[-*+] |[0-9]{1,9}[.)] "

fence(N in 0..) := ticks as T [ info ] nl *( code(N) nl ) %spaces N *SP $T rest nl
                                                                         => ticks(max(len($T), 1 + longest($code, '`'))) $info "\n" join($code, "\n") "\n" ticks(...) "\n\n"
ticks     = 3*'`'
rest      = *'`'
info      = *SP 1*~( SP | LF | '`' )
code(N in 0..) := !$^T [ %spaces N ] r".*"

list(N in 0..) := item(N) *( *blank %spaces N item(N) )                  => join($item, "\n") "\n\n"
item(N in 0..) := marker 1*SP %col M block(M) *( *blank %spaces M *SP %col K block(K) )
                                                                         => $marker " " indent(len($marker) + 1, tight($block))
marker    = bullet => "-" | ordinal
bullet    = '-' | '*' | '+'
ordinal   = 1*9DIGIT ( '.' | ')' )

table(N in 0..) := row as H %spaces N delimiter as D *( %spaces N *SP row )
                                                                         => "#table(\n  columns: " count($H.cell) ",\n  align: " aligns($D) ",\n  table.header(" $H "),\n" $row "\n)\n\n"
row       = '|' 1*( cell '|' ) *WSP nl                                   => join($cell, ", ")
cell      = *WSP *( !cell-end inline ) *WSP                              => "[" trim($inline) "]"
cell-end  = *WSP '|'
delimiter = '|' 1*( *WSP [ ':' ] dash [ ':' ] *WSP '|' ) *WSP nl
dash      = 1*'-'

inline    = code-span | strong | emph | strike | image | link | autolink | escape | text | lone
code-span = r"`[^`\n]+`"
strong    = "**" !SP 1*( !"**" inline ) "**" | "__" !SP 1*( !"__" inline ) "__"   => "*" $inline "*"
emph      = "*" !SP 1*( !"*" inline ) "*" | "_" !SP 1*( !"_" inline ) "_"          => "_" $inline "_"
strike    = "~~" !SP 1*( !"~~" inline ) "~~"                             => "#strike[" $inline "]"
image     = "![" *~( ']' | LF ) as A "](" url as S [ 1*SP title ] ")"      => "#image(" str($S) ", alt: " str($A) ")"
link      = '[' 1*( !"]" inline ) ']' '(' url as U [ 1*SP title ] ')'      => "#link(" str($U) ")[" $inline "]"
autolink  = '<' 1*ALPHA ':' 1*~( '>' | SP | LF ) '>'                       => "#link(" str($) ")"
url       = 1*~( ')' | SP | LF )
title     = DQUOTE *~( DQUOTE | LF ) DQUOTE
escape    = '\\' ~( ALNUM | LF )                                         => esc(rest($))
lone      = '`' | '*' | '!' | '[' | ']' | '<' | '\\' | '|' | '_' | '~'     => esc($)
text      = r"([^`*!\[\]<\\|_~ \r\n]+(_[^`*!\[\]<\\|_~ \r\n]+)*| )+"        => esc($)
nl        = r"\r?\n"
blank     = r"[ \t]*\r?\n"
```

**What it needs, in order of how much it changes the language.**

1. **A value for every rule, and `=> template` to write it.**  A rule's value is its template, or, with none, its children's values one after the other; a rule of characters is its text.  A template is
   strings, `$rule` (the value of that child; for a repeated child, the values joined), `$` (the whole text the rule matched), `$K` (a capture), and calls.  This is `name :: type = ...` and `%emit{}`
   (ABNF.md, "Values at recognition") with a default, so the substrate exists: the value returns up the parse, and giving up a branch drops it, which is why no rollback is needed (C only today).
2. **`x as K` captures a value, not only text, and `$K` reads it back**: in the same rule (`ticks as T ... $T`, the back-reference being built now) and in the template.  `row as H` keeps the row's cells,
   `$H.cell` names them (`.` is scope, as everywhere).
3. **Up references, `$K^` and `$K^R`: a capture of an enclosing rule.**  (The user, 2026-11-03: `.` goes into a scope, so `^` goes up and out of one, and a path written inside-out reads `baz^bar^foo` for `foo.bar.baz`.  `$K` is the rule's own capture; `$K^` the capture K of the nearest enclosing rule that bound it, anonymous, which a helper called from many binders needs (`scope-end = [ "END-" + $K^ ]`); `$K^R` the capture K of the enclosing rule named R, which says which binder is meant and so needs no counting of levels and cannot be shadowed by a nearer rule that binds K too (`!$T^fence`).  There was a first spelling, `$^K` and `$^^K`, with the binder implicit; it was dropped for this one the same day.  Decided; being built.)  The sketch needs two.  The closing fence: `code(N) := !$^T ...` says a line of code is not the opening ticks again, which is
   what a rule reached from `fence` must see of `fence`'s capture, and which no lookahead over a rule can say today.  The other is a fact down the tree (`tight`, the kind of list marker, the table's
   column count).  **An up reference is an implicit parameter**: the generator adds the captured value to every rule on the paths from the capturing rule to the use, as `%col` and `%num` already travel in
   a frame; a rule reachable from two parents that do not both bind K is an error, or the reference is optional (`$^T?`).  So it is hyperrule machinery that exists, not a new runtime.
4. **A small library the templates call**: `rep`, `len`, `join`, `indent`, `trim`, `max`, `count`, `str` (a Typst string), `esc` (Typst's markup escapes), `longest`, `ticks`, `tight`, `aligns`.  The first
   seven are one line each; `esc`, `aligns` and `longest` are a few lines of C, which is where `{ code }` stays (the principle: code is allowed when it shrinks the total).
5. **Output without a tree**: the C backend builds the value as the parse returns (an arena, and a rope or a length-first buffer so a document is not copied once per nesting level).

**Estimated size.**  544 symbols for grammar and output, against 1,876 for grammar and walker; the library adds about 150 to 250 symbols once, for any grammar.  So the rewrite form is about 2.4 to 3.4 times smaller
than the walker, and the walker disappears (no tape reader, no tag switch, no indentation bookkeeping: `indent(n, ...)` is the nesting).

**What it does not remove.**  Some of the sketch is judgment, not mechanism: `esc($)` must know it is at the start of a line (`= - + /`, `1.`), which wants `bol` as a fact the escape reads (`$^bol`) or the
walker's `at_ls`; the tight-list rule; Typst's own limits.  A converter is also one-way: the tree is gone, so a second use (a table of contents, a word count) needs a second grammar or a tape.  Both of
those argue for keeping the tape and the walker as the general answer and the rewrite form as the compact one for a straight conversion.

**Open (the user).**  (a) Is `=>` followed by a template the right spelling of "this rule's value", given `=>` also means a switch of grammar and a fact (section 15)?  The one arrow reads as "the consequence of
a match", and a template is a consequence.  (b) `$^K` for an up reference, or another sign.  (c) Whether a default of "concatenate the children" is wanted, or every rule must say.


## 26. Reader and generator fixes found while writing the Markdown grammar (2026-11-03; queued, nothing built)

Each was met writing `corpus/markdown`; the first two are the user's decisions, the rest are findings that read as limits and not as design.

1. **`'c'` is `"c"` (the user).**  A character literal is a literal of length one with the other quote character; the two spellings are one thing, and the quote character only saves an escape (`'"'`, `"'"`).  Today the reader makes `'c'` a bare
   code point, so `!'b'` and `&'c'` are refused, a repeated `*'-'` needs a rule of its own, and `'\'` is the only backslash.  What a literal means is decided where it stands (text in a rule of characters, a word in a phrase rule when it begins
   with a letter).  About 40 single-quoted literals in the repository hold a letter or a digit (mostly `grammars/obconf_*`); the byte-identity comparison finds any that change.
2. **`'\'` for a backslash (the user)**, not `"\\"`: a backslash directly before the closing quote reads as a backslash (`\'` is still an escaped quote).
3. **A lookahead over a sequence (the user's question: "how is a rule not a sequence?").**  `!( a b )` and `&( %spaces N 'x' )` are read as a lookahead over an anonymous rule, lifted when the grammar is read, which takes the parameters it uses.
   Today only a literal, a rule or alternatives of those are accepted, and the sequence has to be named.
4. **`hidden` and `!`/`&` over any rule, in every layout (the user: "ws is structure").**  Today `hidden` accepts a rule only if it is pure text, and a lookahead under `layout tape` accepts a rule only if it writes nothing.
   Both need the same thing: a silent variant of a rule, the same function with the writing of nodes switched off.  With it, `hidden nl` works when `nl` holds `eol`, and `!closer(N)` works when `closer` holds `%spaces N`.
5. **`bol` and `eol` are text for `hidden` and for rules of characters.**  A rule that holds `eol` is refused as `hidden` ("it builds structure").
6. **A `%spaces N` at the start of a repeated group reads N as lost, in `corpus/markdown`** (not in the smallest grammar that has the same shape): `table(N) := row %spaces N delimiter *( %spaces N row )` reads no data rows for N > 0, and
   `*( %spaces N *SP row )` does.  The repro is in `/home/matthew/hbnf-repro-spaces/` (README.txt, the failing grammar, the input, five variants).
7. **A pattern rule's instances are named for the pattern** (`marked-x42x42`) in the tape and the tree; a rule written with the pattern as its body would want the caller's name (`strong = marked("**") | marked("__")` as one node `strong`).
8. **Up references (section 25)** are the one item here that is a feature and not a repair.

**More findings from the GraphQL grammar (`corpus/graphql`, 2026-11-03; each found by the agent that wrote it, none fixed).**
9. **Ada**: a literal alternation holding `"type"` makes the enum value `<Rule>_Type`, which collides with the generated type of the same name and does not compile (`( "type" | "interface" )`).
10. **Rust**: a rule called `body(X)` collides with the generated `parse_body_<rule>` functions (`parse_body_root_operation` is defined twice).
11. **A negative lookahead over a rule that itself ends in a negative lookahead** (`!bare`, `bare = ... !( ... )`) works in C and wrongly refuses in Rust and Zig; a positive `&adds` is the workaround.  This is a backend bug, not a limit.
12. **Ada** writes a raw TAB for `0x09` inside an Ada string literal when a character rule has a lookahead and is read a character at a time; the file does not compile.
13. **`word`** is renamed `word-rule` when it is a regex or holds a group under a repetition, and the keyword boundary then breaks (`scan_word` undefined in C).
14. **A token exception** `name - "on"` with a literal operand is refused with "expected a literal, name, or group"; the operand has to be a rule.
15. **Letters in a rule of characters** must be `'e'`, not `"e"`: `"e"` is read as a whole word and fails on `e10`.

**More findings, from the XML grammar (`corpus/xml`, 2026-11-03; none fixed).**
16. ~~**`--layout=tape` with a back-reference** wrote C that did not compile (`cl_tag_N` undeclared).~~  Fixed: the pieces of one sequence (`qname as tag` and the `"</" $tag` after it) name the capture alike, and a rule made only of an up reference (`code_up1`) stays a phrase rule that a lookahead may look at.  `tests/tapecap.sh` runs the back-reference, up-reference and up-scope grammars as a tree and as a tape and compares the verdicts.  Still open, and not about captures: item 63 (HTML as a tape).
17. **`--layout=tape` and a lookahead over a rule** (`legal = *Char !any`, `document = &legal ...`) is refused ("an %emit inside a lookahead"), also when `legal` is `hidden`; the workaround is about three times slower (37 ms against 11 ms per MB).  The silent variant of item 4 is the cure.
18. **Ada**: a pattern rule's instance is named from its literal arguments, and a `-` or `_` in an argument gives `__`, which Ada refuses (`t("--")`); passing the literal through a rule avoids it.  The same as item 7, for Ada.
19. **Rust**: a rule named `default` becomes a struct `Default` that shadows the trait, and `Default::default()` fails to compile.
20. **Rust**: the generated `let mut cp_tag = 0usize` is assigned again before it is read, which `-D warnings` rejects (`unused_assignments`); `tests/xml.sh` shims `rustc -A unused-assignments`.
21. **C**: a NUL byte ends the text, so `<a/>` then a NUL and more is accepted; and an overlong UTF-8 sequence (`\xC0\x80`) is read as valid while `\xFF` is refused.
22. **A lookahead rule inside a rule of characters always warns** ("read a character at a time"); `legal`, `chardata` and the `quoted(...)` and `till(...)` instances all do.  **Fixed for C (2026-11-03, on the question "why is the C XML parser slower than expat").**  A rule of text with a lookahead and a repetition is a rule of characters and is scanned in place: the scanner has an `Iter` atom (a repeated group, or a repeated rule that is not a flat class, whose one time is a function `loop_*` returning the length of the longest branch that matches, like the `look_*` of a lookahead), and a lookahead may sit anywhere in the rule, in a group too; `Group` is accepted in such rules.  A rule of characters that is one only for this reason (`HBNF_Grammar.Is_Wide_Rule`) also gets a faster loop for a repeated class (a 128-entry table for ASCII, a decode for the rest) instead of one decode per alternative per character.  Only C: `hbnf` says `Set_Scan_Look` for `--backend=c`; Rust, Zig and Ada still read these rules a character at a time and still warn.  The generated C of every grammar without such a rule is byte-identical (graphql, shell and XML, which have them, change by design).  **The condition (added after the YAML and JavaScript suites found the first version too wide):** a rule is scanned only where at most one alternative can begin at a position, which `Choices_Ok` proves from the first bytes (of the UTF-8) each alternative can begin with: every choice in the rule, in its groups and in the rules it names is between alternatives that cannot be empty and share no first byte, or between single code points; a lookahead is a test and its contents are not choices.  Where it cannot prove that, the rule stays a phrase rule and the warning stays (YAML's `dirs`, JavaScript's `number`).  A rule that only names a scanned rule is not made a rule of characters by it (so nothing about the tape layout or the tree of a rule that did not warn changes).  Not changed: the warning stays for the other backends; a nullable body of a repeated group ends the loop (a zero-length time is not counted); `--layout=tape` with `&legal` now works for the lookahead (it names a token), the back-reference of item 16 still stops XML.

**More findings, from the HTML grammar (`corpus/html`, 2026-11-03; none fixed).**
23. **A hyperrule's literal argument ignores the file's `sensitivity string %i`**: `f(N) := "<" N ">"` called `f("a")` refuses `<A>` and accepts `<a>`; the workaround is `i"a"`.
24. **`$K` compares bytes**, so a closing tag cannot be case-insensitive (HTML folds case: `<DIV>x</div>` is legal, and the grammar refuses it).  **Decided (the user, 2026-11-03): `$K` keeps the property of what it back-references**: it compares as the captured element matches (an `i"..."` captured is matched ignoring case, an `s"..."` exactly), and where that element carries no flag of its own, as the grammar's `sensitivity` says.  Section 10 recorded the byte comparison only to keep the output of the `%same` grammars the same; a grammar under `sensitivity string %i` that uses `$K` changes, and the byte-identity comparison finds it.  **BUILT 2026-11-03**: a `$K` of an `i"..."` literal ignores ASCII case, of an `s"..."` is exact, and otherwise follows the file's `sensitivity`; `corpus/html` now accepts `<DIV>x</div>`.
25. **`as K` and `$K` in the same sequence but in different group alternatives** (`"<" ALPHA as t ( "/>" | ">" "</" $t ">" )`) make the C backend write code that does not compile (`cl_t_3` undeclared); it should be a message from the reader.  **Fixed 2026-11-03**, by the machinery of up references, not by a message: the capture is passed to the group's rule in the frame of numbers, so it compiles and works (also in an option, a repetition, a lookahead and a join, `tests/upref/group.hbnf`, `tests/backref/join-group.hbnf`).
26. **A rule named `text` collides with `parse_text` in Rust and Zig** (fine in C), as `word` and `default` do; the generator should rename a rule that collides, as it does for `word`.
27. **In an island (`include ... as x`)** a hyperrule defined in the guest (`sym(S) := S blank`) gives "rule `S` is not defined in grammar `js`", and a lookahead on a guest rule (`"var" !id-char`) gives "rule `id-char` is not defined in grammar `js`" though it is defined there.  **The lookahead half is fixed 2026-11-03** (a name after `!` or `&` was read as the name of a capture, not of a rule); the hyperrule half is not (`^.list(^.name)`, a hyperrule defined in the host and called from the guest, is the way round it).
28. **A generator crash**, `CONSTRAINT_ERROR hbnf_c.adb:5851`, for `chars(X) := 1*( ref / amp / !( X / "&" ) char )` called as `chars( space / DQUOTE )` (alternatives passed as a pattern); a named rule as the argument works.  Not shrunk below a copy of `corpus/html/html-tokens.hbnf`.
29. **A multi-character lookahead in a rule of characters** (`!"-->"`, `!"]]>"`) makes the rule a list of one-character nodes and the generator warns: the same cause as item 22, seen as a tree effect.  Quick at run time.
30. **The root after `include "html.hbnf"`** with new rules in the including file became the last new rule, not the included file's first; overriding existing rules keeps the root.
31. **`=> grammar(js)` after `<script>`** generates and changes nothing (the switch replaces white space only and HTML skips none); and there is no way back, since `grammar(x)` needs an `include ... as x` and a host cannot include itself.  This is phase 2 of the switch.
32. **Rust**: a rule using `as` assigns a value never read, and `-D warnings` refuses it (also item 20); `tests/suite.sh` now takes `RUST_LINTS`.
33. **Tree-sitter** drops lookaheads, so comments and raw text over-match.


## 27. JavaScript and CSS as islands in HTML (the user, 2026-11-03; decided in outline, nothing built)

The user: `js` and `css` should be islands in `html`, each in its own grammar file.  So `corpus/js/js.hbnf` and `corpus/css/css.hbnf` are standalone grammars, and `html-islands.hbnf` includes them (`include "../js/js.hbnf" as js`).

**Two things the island mechanism does not do yet**, both found by the HTML grammar's island variant (section 26, items 27 and 31):
1. **A guest with its own white space.**  A grammar included `as x` shares the including grammar's `ws` or says `whitespace none`; one with a `ws` rule of its own is refused ("one white-space rule").  JavaScript and CSS both have their own (comments,
   line terminators that matter to JavaScript's semicolon insertion), so an island needs the per-grammar scanner that the switch `=> grammar(x)` already has (stage 2: `skip_ws` is one dispatch on the current grammar).
2. **A bounded island.**  The end of a `<script>` is decided by the HTML tokenizer (the first `</script`), not by the JavaScript inside it; today the guest runs on the host's text and stops where it stops, so `var a = "</script>";` ends
   the script at the wrong place.  The host should first take the raw text, and the guest should read exactly that text:
   `script = "<script" attributes ">" raw as R "</script" ">"` with the guest applied to it, written `js.program in $R` (proposed spelling; `in` is already the word of a parameter's domain).  The guest must consume all of the text, or the
   element fails; the positions the guest reports are the host's.  This is `x as K` and `$K` (built) used as an input, not as a match.

**The grammars.**  `corpus/js`: ECMAScript, the Script goal and the Module goal if it is cheap; the lexical ambiguities of JavaScript (a `/` is a division or a regular expression; template literals nest; automatic semicolon insertion; the contextual
keywords `async await yield of get set static let`) are written for a scannerless reader, which tries a regular expression where an expression is expected and a division where an operator is.  `corpus/css`: CSS Syntax Level 3 (rules, at-rules,
declarations, blocks, functions, custom properties, comments, the escapes of identifiers and strings) with the selectors of Level 4 and the value syntax of the common properties as far as is cheap; roots `stylesheet` (a `<style>` element) and
`declaration-list` (a `style=""` attribute).  The attribute values of HTML (`onclick`, `style`) are the same islands with other roots.  Both are standalone and tested alone first.

**Order.**  (1) the two grammars, as agents; (2) island with its own white space, then the bounded island, in the generator (after the speed work on the C scanner, which touches the same files); (3) `html-islands.hbnf` over the real grammars, and the
test the stub could not pass: `var a = "</script>";` read as the browser reads it.

**Later, from the same sign (the user, 2026-11-03).**  `^` as "out of" also fits islands: inside a guest grammar, `^.rule` names a rule of the including grammar (`^.^.rule` two out, as `../name`), an explicit way out that is not a fallback (missing names stay missing); the `$` sign tells it from the capture forms.  Decided (the user: "why would you say not to build it?"), being built;
needed when a guest has to call back into its host (an HTML `<script>` that has to end where the host says, or a template language whose guest reaches the host's names).

**More findings, from the SGML grammar (`corpus/sgml`, 2026-11-03; none fixed).**
34. **Under `sensitivity string %i` keywords have no word boundary** (a plain `strncasecmp` prefix), so `ID` matched the front of `IDREF`.  The boundary turns on only if the grammar names `word` or lists `keywords`, and naming `word` makes every keyword unusable as a name.  The workaround is to write the longer keyword first, which lets `<!ELEMENTa` through in a `.dtd`.
35. **A literal passed as a word parameter** (`decl(K, P)` with `K` = `"ELEMENT"`) does not take the file's `%i`, and generation stops with "keyword written both with i"..." and without" (as item 23 says for HTML; literals inside a pattern argument do work).
36. **A rule named `flag` is silently the built-in `flag`**, with no warning, unlike `word` and `atom`.
37. **A rule made only of literals and token rules is itself a token and skips no blanks inside it** (`appinfo = "APPINFO" ( "NONE" | literal )`); the same words with an optional or a repetition in them are a phrase.  Silent and inconsistent.
38. **A pattern rule inside an island fails**, so the island experiment writes `content(D)` out three times (the same as item 27 for hyperrules).
39. **Ada**: a self-recursive list rule (`x = *( "<![" x "]]>" | y )`) emits `"Ignored_Type" is undefined`; giving the entry its own rule cures it.
40. **The C backend refuses a lookahead inside what a `ws` rule repeats; Rust, Zig and Ada accept the same rule silently.**
41. **A declaration that spells its own delimiters** (the SGML declaration's `SYNTAX` section) cannot be a switch, even once token rules can be overridden: only a named syntax can be.  `=> grammar(x)` for a CDATA marked section works in C but makes the text white space, which is not in the tree; a raw token is simpler.

**More findings, from the CSS grammar (`corpus/css`, 2026-11-03; none fixed).**
42. **White space that means something cannot be a skipping `ws` rule.**  The skipping rule eats blanks before the next element is tried, so nothing after it can ask whether there were any (CSS's descendant combinator, and the blanks around `+` and `-` in `calc()`).  `corpus/css` uses `whitespace none` and three rules written out: `ws` (any), `blank` (one or more), `gap` (a real space, with comments allowed around it).  A way to ask "was there white space just now" (a lookbehind, or a skip that reports) would let a grammar keep the skip.  It also means CSS has no skipping `ws`, so the island limit that stops it is not item 31's but item 27's (a hyperrule in a guest).
43. **`--layout=tape` produces C that does not compile for `css.hbnf`** (`parse_rule_ws` undefined inside `parse_loud_keyframe`); renaming `ws` cures it; a small grammar with a hidden `ws` compiles.  Not shrunk.
44. **A pattern instance holding a lookahead warns "read a character at a time" when its argument is not a bare literal** (`at([ vendor ] i"keyframes")`).
45. **With `sensitivity string %i` in a guest, an island error points at the sensitivity line** (`css-tokens.hbnf: 6: 13`) instead of at the hyperrule that is not defined in the guest (`css--at(N)`).

**More findings, from the JavaScript grammar (`corpus/js`, 2026-11-03; none fixed).**
46. **A lookahead is evaluated after the blanks are skipped**, so it cannot see a line end (`program = "a" &nl "b"`, `nl = *blank LF`, `ws` skipping LF refuses `a`, line feed, `b`).  Only `eol` sees where the previous token ended.  This is what automatic semicolon insertion needs, and the grammar is written around it: every token that can end a statement ends with `*inl` (the blanks and comments on its line), and `ends(X) := X ";" | X rbrace-ahead | X eof | X eol`.
47. **A rule that ends in an optional or repeated element ends after the blanks**, so a following `eol` fails (`e = id *tail` refuses; `e = id 1*tail | id` accepts), and the C ladder optimisation (`a = b *(op b)`) does the same.  The grammar writes every statement-ending rule as `a b | a`, never `a [ b ]`, which depends on this staying so; the V8 tests would catch a change.
48. **Shared-beginnings factoring is off in rules with first-byte dispatch, and when the rest of an alternative starts with a block** (`eol`, `!x`, `&x`): `x = id ";" | id eol` parses `id` twice, so failing parses compound with nesting.
49. **A rule that `ws` reaches and that holds a lookahead is checked as a plain rule**: it refuses `*( group )`, a string literal as the operand (`0x2B` works), and `bol` in a group, with a message that is cut off after "but" and names no rule.  The same `ws` passes in a `whitespace none` file.
50. **A table of about 700 ranges followed by anything is copied once per alternative**: `x = id-start-uni *id-continue-uni` writes 126 MB of C, and adding a multi-character alternative to the same repetition makes the generator not finish.  (corpus/js/js-unicode.hbnf is generated by corpus/js/idtables.py from Unicode 16.)
51. **Keyword mode is on only if some rule uses `word` or `atom`**; defining `word` alone does nothing and nothing warns.  Without it every letter-led literal matches the front of a longer word (`"new"` read `newValues`, `!"class"` refused `className`).  The same cause as item 34.
52. **Zig is exponential in nesting where C is linear**: about 3.5 times per level (`x = [[[[[[[[1]]]]]]]];` takes 22 s at 8 deep, 6 s at 7, 2 s at 6; the same in C at 22 deep takes 1 ms).  The Zig suite keeps its test nesting at 4 or less to pass its 30 s guard.  A backend defect, and the most serious finding of the grammars so far.
53. **`!` and `&` accept no code point** (`!0x7B` is refused; a rule is needed); and an island `include ... as js` fails first with the hyperrule-in-guest error (item 27).
54. **A wish**: a one-line way to say "this token takes the blanks of its line", for the `*inl` that ends every token in item 46.

**More findings, from the up references and `^.rule` (2026-11-03; the first four fixed in the same patch).**
55. **A frame for the first rule**: a rule that keeps a capture in the frame (an `x as K` read by a group, an option or a lookahead) and is the first rule had no frame to keep it in, since the entry point made none.  Fixed: the entry point makes the first rule's frame (C, Rust, Zig, Ada).
56. **The reader read the frames of the first reading into the second**: `hbnf` reads a grammar twice in a process, and the table of frames was kept, so a rule made a frame by the first reading was refused as called without its arguments by the second.  Fixed: the table is cleared when the second reading begins.
57. **The greedy-repetition check took `$K` as matching nothing**, so `*( code LF ) $t extra LF` was refused for the text `<U+000A>`.  Fixed: the look stops at a `$K`, whose text the grammar does not know.
58. **A lookahead of a name in a scope** (`!^.stop`, `!sql.x`) was not resolved to the scope's rule (see item 27); fixed.
59. **Not fixed, in the generator as it was: a repeated group whose first element is a lookahead, followed at once by a `$K`**, loses the lookahead and the list entry gains the `$K` (C; `doc = "[" 1*ALPHA as t LF *( !"]" ALPHA LF ) $t LF`, found with the build of main).  A literal before the lookahead in the group is the way round it.
60. **Not built**: a rule that uses an up reference and also sets numbers with `%col` or `x %num j` is refused (the numbers the up reference passes go in front of the others); a lookahead over a rule that itself uses an up reference is refused (write the up reference in the lookahead); `^.name` in a root-bound guest is checked only by the name, so a plain `name` written in the same guest beside it is also accepted when the root defines `name`; the `$K` writer (`--writer`) writes nothing for an up reference.

**From the memory reduction of the C tree (2026-11-03; item 61 not fixed, 62 a decision recorded).**
61. **The generated tree dump (`--ast-tools`, `dump_<root>`) segfaults in its recursion for the JavaScript and COBOL trees**, at the baseline too, so those two are not tree-compared before and after a change of layout, only by their suites.
62. **The shape of the C tree changed where it paid** (the user, 2026-11-03: apart from the obconf grammars, the structure of the tree and of the tape is free to change).  A node that is one of several alternatives overlays the fields no alternative holds together, and `_alt` (from 1, in written order) says which is valid; a small struct member of such a node, and the members of a pure choice, are held by value (`n->object.object_1`, `expr->keyval`).  A failed attempt rewinds the arena.  Each is switched off by `--no-overlay` and `--no-unwind`, and a grammar with an action, `%emit`, a context or forks keeps the old layout (which is how the obconf grammars stay as they are).  The memory of the YAML tree for a 2 MB document went from 29.0 to 19.2 MB, XML 14.4 to 9.4 MB.  Not done, with estimates: list links packed into arrays (about 25% of JSON and TOML, 19% of XML), embedding the 16-byte pure choices in their parent, options as nullable pointers, a tagged pointer for `_alt`.
63. **`--layout=tape`: a lookahead over a rule that writes something is refused** (`an %emit inside a lookahead`).  The smallest case: `doc = 1*( "<" name !tc ">" )`, `name = 1*ALPHA`, `tc = !( SP / ">" ) ALPHA`.  In a tape every phrase rule that holds a node is a rule with emits, and a lookahead may not look at one (the tape could be put back by `rollback { tape_n }`, but the lookahead code does not do it).  Only the rules `x_upN` that an up reference makes of `!$K^` stay phrase rules (they write nothing).  `corpus/html/html.hbnf` (`!tag-char`) does not generate as a tape because of it.
