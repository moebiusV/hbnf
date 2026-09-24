# hbnf: Compact, Fast Configuration Parsers from Extended ABNF

*System design paper (draft).  Target: USENIX ATC / LISA.*

## Abstract

Configuration file parsers are the unglamorous workhorses of systems software:
every daemon ships one, and they are almost all written the same way — a
hand-written lexer plus a yacc grammar.  This paper presents **hbnf**, a schema-driven
parser generator built on an extension of RFC 5234 ABNF.  A schema is a
grammar; hbnf compiles it to a self-contained parser (declarations, lexer, and
parser in one file) in C, Rust, Zig, or Ada, with the C backend exposed to
Python, Ruby, Perl, and newLISP over FFI.

The design departs from the classic lex/yacc split in one way that matters:
the lexer is not a separate, fixed stage.  Token definitions live in the
grammar, expressed either as character-level ABNF (the general, executable
spec) or as a hand-written scanner function — a *jet* — that is dropped in for
speed and cross-checked against its ABNF twin.  Moving the lexer into the
parser this way lets a grammar distinguish `a > b` from a bareword containing
`>` using ordinary rules, and lets a MIME type or a money amount be written as
`str "/" str` or `1*DIGIT "." 2DIGIT` without touching any lexer code.

hbnf is evaluated on a synthetic pf-style firewall ruleset — the motivating
workload, where production rulesets exceed 100,000 rules.  The current
generated C parser consumes 100,000 rules (8.5 MB) in 72.7 ms (1.38 M rules/s,
111 MB/s, 127 MB peak RSS).  The same grammar notation compresses OpenBSD's
httpd configuration grammar from 2,785 lines of parse.y (63 rules, 79 keyword
tokens) to under two hundred lines.

## 1. Introduction

Every UNIX daemon needs to read a configuration file, and the tradition is to
write a lexer and a yacc grammar by hand for each one.  OpenBSD's tree is the
purest expression of this: more than a dozen daemons — pfctl, bgpd, httpd,
ntpd, unwind, dhcpleased, and others — each ship a `parse.y` with a hand-written
`yylex()`.  Those lexers are near-identical copies of one another, a few
hundred lines of `lgetc`, keyword tables, and `strtonum`; the grammars share
one skeleton (a top-level list rule, `TAILQ`-driven actions, a `yyerror`
handler).

Two things make this pattern expensive.  First, it is *repetitive*: the same
lexer is rewritten for every program, and the grammar is a third again as long
as the config language it describes.  Second, it is *stiff*: the split between
lexing and parsing is baked in.  A token is whatever the lexer decides to
collapse, and the grammar can only match what the lexer hands it.  When a
language wants `1.2.3.4` to be an IPv4 address, or `1.50` to be a money amount,
the lexer grows a special case (`allowed_to_end_number` in OpenBSD's lexer is
exactly this, and it is a hack).

hbnf is built around a different premise: **a token is a grammar rule over
characters, and the lexer is generated from the grammar's token definitions,
not written separately.**  ABNF (RFC 5234) is already a character-level
notation — its core rules are `DIGIT`, `ALPHA`, `SP`, `DQUOTE`, and its
literals are strings of characters.  The schema language is ABNF, extended with
the typed, named subrules a parser generator needs; the whole parser is emitted
from that schema.  Where hand-written speed is required — a
token that appears a million times — the schema can name a hand-written scanner
function as that token's definition, cross-checked against a BNF twin.  The result matches the readability of a grammar
notation with the speed of a hand-written lexer.

Contributions:

1. An extension of ABNF into a parser-generator schema language (typed named
   subrules, repetition, alternation, multi-line rules, an OpenBSD-style
   `parse_config` entry point and point-of-error handler).
2. A design that moves lexing into the parser: token definitions are BNF over
   code points, with hand-written scanner functions ("jets") as a
   speed-equivalence escape hatch, cross-checked against the BNF.
3. Four code generators (C, Rust, Zig, Ada) and an FFI story for dynamic
   languages, with a benchmark on 100k-rule firewall rulesets.
4. A privsep wire shape for the C backend: an id-ref serializer and rebuild
   side that flatten the typed tree to cross the imsg boundary, matching how
   OpenBSD's privsep daemons actually hand configuration to their children.

## 2. Background

### 2.1 ABNF

ABNF (RFC 5234) is the grammar notation behind the IETF's protocol
specifications.  A grammar is a set of *rules*:

```
rule    =  alternation
alternation = concatenation *( "/" concatenation )
concatenation = repetition *( repetition )
repetition = [ repeat ] element
repeat  = 1*DIGIT / ( *DIGIT "*" *DIGIT )
element = rulename / group / option / char-val / num-val / prose-val
```

Its appeal for configuration is that it is *already* a character-level
notation: `ALPHA`, `DIGIT`, `HEXDIG`, `SP`, `HTAB`, `CR`, `LF`, and `DQUOTE`
are defined as single-character classes, and a literal `"example"` is a string
of characters, not a token.  What ABNF lacks is everything a parser generator
needs beyond matching: it has no notion of a *value*, a *type*, or a *tree* —
a rule matches or it does not, and the spec deliberately stops there.

### 2.2 The lex/yacc split, and why it exists

Separating lexing from parsing is a genuinely principled engineering decision,
not an accident of history.  A lexer recognizes a *regular* language (it is a
deterministic finite automaton); a parser recognizes a *context-free* one (it
is a pushdown automaton).  The split buys three things: the parser's grammar
stays readable because it reasons about word-sized tokens rather than
characters; the lexer is a simple, fast table-driven loop; and the whole thing
is easier to make deterministic.

But nothing about the input forces the split.  A character is a perfectly
good token.  If you feed a yacc-style parser characters instead of words, it
still works — it just matches `1*ALPHA` instead of a single `IDENT` token.
The real question is not "must there be a lexer?" but "who decides what a word is?"  In
the classic split, the lexer decides, once, globally, by way of a hard-coded
word-character set.  That one global decision is what makes `1.2.3.4` (or
`a>b`) need a lexer special case.

### 2.3 The OpenBSD parse.y pattern

OpenBSD's config parsers are the concrete starting point for this work.  Each
`parse.y` is a hand-written `yylex()` plus a yacc grammar whose actions build
`TAILQ` lists.  The lexers differ only in their keyword tables and a few
domain quirks (pfctl and bgpd have an operator switch; the rest are identical
in shape).  The grammars differ more — each encodes one daemon's config
language — but they share a skeleton: a `%token` keyword table, a top-level
list rule, `TAILQ` action code, and `yyerror`.  Two details matter:

- **Domain-specific tokens are validated in actions, not lexed.**  An IP
  address, a MAC address, an OID are lexed as a plain STRING or NUMBER and
  checked with `inet_pton`/`strtonum` in the grammar action.  The lexer's
  `allowed_to_end_number` flag exists to re-lex a digit run as a string when
  the next character is a word character, so `1.2.3.4` becomes one STRING that
  the action can hand to `inet_pton`.

- **The result is fast.**  pfctl parses 100k-rule rulesets in a few hundred
  milliseconds because the lexer is a hand-written loop and the grammar is
  LL(1)-ish, with no backtracking.

- **There is no generic "conf tree".**  The yacc actions *are* the config
  builder: they call helper functions (`new_peer()`, `new_filter()`,
  `add_mrt()`, …) that allocate and link nodes directly into the daemon's own
  `struct *conf`, mutating it incrementally as the shift/reduce runs.  hbnf
  inverts this — the parser returns a typed tree and the program walks it
  afterward.  For configuration that is the same work split across two phases;
  for a parser generator it is the difference between a grammar welded to one
  daemon's struct layout and a grammar that is reusable and self-describing.

- **The tree crosses a process boundary as ids, not pointers.**  The daemon
  family is privsep: the parent parses, then ships the configuration to
  unprivileged children over imsg, and a pointer cannot cross that boundary.
  Objects therefore carry an id (`objid_t`, `rl_conf.id`) and refer to each
  other by id; the parent serializes the tree piece by piece
  (`config_setrelay()`, `config_settable()`, `imsg_send_config()`), and each child
  rebuilds its own copy, resolving ids with per-type `*_find()` helpers and
  merging into its live tree (`merge_config()`, `config_purge()`).  Reload
  parses a whole new tree and merges it.  For these consumers a pointer-linked
  tree is the wrong shape — the wire form is a flat id-ref stream plus a
  serializer — which is exactly what hbnf's `--idref` output emits (§3.4).

hbnf's goal is to get that speed and that clarity from a *declarative* schema,
without the hand-written lexer and without the token-level straitjacket.

## 3. Design

### 3.1 Schema = grammar + types

An hbnf schema is an ABNF grammar in which a rule's *name* carries its type.
Consider a minimal server config:

```
server    = name listen root redirects aliases tls
name      = str
listen    = "on" iface "port" port
iface     = word
port      = u16
root      = str
redirects = *( "to" dest / "to-group" group )
dest      = str
group     = word
aliases   = 1*alias
alias     = str
tls       = flag
```

Three things are happening that plain ABNF does not do:

1. **Named subrules become typed fields.**  `server` has fields `name`, `listen`,
   `root`, `redirects`, `aliases`, `tls`; the generator emits a struct (or
   record/enum) whose members are those rules' types.  A rule that is a
   literal alternation (`"in" / "out"`) becomes an enum; a rule that is a
   repetition (`1*alias`) becomes a list.

2. **Core rules are typed sugar.**  `str`, `word`, `int`, `u16`, `flag`, and
   the `u8..u64`/`i8..i64` families are built-in *scalar* rules with known
   representations (`const char *`, `long long`, `uint16_t`, `bool`, …).  They
   are not magic: as §4 explains, each is sugar over the character stream.

3. **Match-and-skip literals.**  Quoted literals in a sequence (`"on"`,
   `"port"`) are matched and discarded, exactly as keyword terminals in yacc.
   They do not become fields.

The generator emits a *self-contained* parser: forward declarations of every
type, the type definitions in dependency order, the `parse_<rule>` functions,
and the lexer — one compilable file per backend.

### 3.2 The conf wrapper and the point-of-error handler

For the OpenBSD use case, hbnf also emits a `parse_config(filename)` entry that
matches the shape of a daemon's existing config loader: it reads the file and
produces a global root, with an overridable error handler.  The handler is
invoked at the point of error with the message and a caret rendering of the
exact position — line, column, and the offending token underlined:

    on wg0 port oops
                  ^

The daemons' own `yyerror` does not do this: it logs `file:line: message` from
the lexer's line counter, with no column and no caret, so a mistake in the
middle of a long line is reported only by line number.  The caret is thus a
small but real improvement over the convention it replaces, and it extends
naturally to a *span*: an "unclosed `{`" error can point both at the token that
failed to match and at the opener that began the production — which is what the
reader actually needs when the two are not on the same line.  The same entry
point is what the FFI bindings expose (`conf_ptr()` returns the parsed root).

The wrapper reads a config the way `yyparse` does, one statement at a time
(the schema's `statements` directive).  A statement ends at a newline outside
braces; each is lexed, parsed and, in a daemon binding, handed to the actions
and freed before the next is read.  A syntax error is reported and the parse
goes on with the next statement, so every error in the file is reported, as
parse.y's `error` rule does.  `macros varset` and `includes include` name the
rules whose statements define a macro and include a file, which gives parse.y's
`$name` expansion and `include`.  Holding one statement at a time is what
brings the ntpd binding's memory close to byacc's: on a 100,000-sensor config
(7 MB), peak RSS is 19 MB, against 12 MB for ntpd's parse.y through byacc and
82 MB when the whole file was tokenized and parsed at once.  Most of what is
left is the file itself, which the wrapper reads whole.

### 3.3 Extensions over ABNF

- **Multi-line rules.**  A newline before a `/` is a continuation, so a long
  alternation reads as a column of alternatives rather than one horizontal
  line — which is what makes the httpd grammar (§5) readable.
- **Repetition.**  `*`, `1*`, and `n*m` with the usual ABNF semantics, plus
  `[...]` as shorthand for `0*1`.
- **Comments.**  `;` to end of line (the IETF convention), with a `#` comment
  convention in the emitted lexers for the config files themselves.
- **Unicode.**  The input is treated as UTF-8 and decoded to code points; the
  matcher operates on code points, and the emitted parsers emit UTF-8.  A
  literal can name a non-ASCII character (`"café"`), which is meaningful only
  once the lexer's unit is a code point rather than a byte.

### 3.4 The privsep wire shape

The tree a privsep daemon consumes is not the pointer tree a single-process
parser would build, because that tree has to cross the imsg boundary (§2.3).
The C backend therefore emits a second shape on request — the `--idref` wire
form — alongside the ordinary pointer tree, so a schema yields both the
in-process tree and the cross-process representation.

Every struct and list node gains `objid_t id, parent;`.  A generated
`serialize_<rule>` walks the tree in pre-order, assigns ids in traversal order,
and emits one flat record per object through an abstract
`emit(type, ptr, len)` callback.  A child records its parent's id, which is
always smaller and already sent, so a consumer rebuilds the tree in a single
forward pass.  Strings are length-prefixed on the wire; ids replace only the
structural pointers, never the scalar leaves.  The symmetric rebuild side
emits a `decode_<rule>` per type that reads one flat record back and recurses
into its children in field order, plus a `config_decode()` entry over the whole
record stream, so each process keeps its own separately allocated tree and none
of them is the parser's original.

The traversal itself is not new — hbnf already generates the visitor and fold
of §8, and a pretty-printer like the daemons' `printconf.c` is just one more
visitor over the typed tree.  What `--idref` adds is the id-ref
*representation*: a third generated pass that walks the same tree once more and
emits it as the flat id-ref stream a pointer cannot carry — the wire-form
counterpart of the daemons' `config_set*`/`config_get*` serialization rather
than of their `printconf.c` text printer.

## 4. Moving the lexer into the parser

The central idea is that the token definitions are themselves grammar rules,
and the lexer is generated from them.  This collapses the classic split.

### 4.1 The character stream

The generated lexer is minimal: it skips whitespace and comments and emits one
token per *code point*, with quoted strings the only composite token it still
forms on its own.  Everything else — barewords, numbers, operators — is left
to the grammar.  A bareword is just a rule:

```
bareword = 1*( ALPHA / DIGIT / "." / "_" / "-" )
```

and a number is `1*DIGIT` with an optional sign.  This is why the "who decides
what a word is" question disappears: the grammar decides, per rule, and two
rules can disagree (`mailaddr` includes `@`, `bareword` does not) in a way a
single global word-character set cannot express.

### 4.2 `a>b`, and CSTRING as sugar

The motivating micro-example is `a > b` with no whitespace.  At token level,
the lexer must be *told* that `>` is not a word character, so `a>b` lexes as
`a` · `>` · `b`.  At character level the grammar says so:

```
comparison = bareword ">" bareword
```

The bareword rule stops at `>` because `>` is not in its alternation.
No lexer knowledge of operators is needed, and — crucially — the boundary can
differ per rule.

The same logic reaches quoted strings.  A C string is a regular language:

```
str = DQUOTE *( %x20-21 / %x23-7E / ( "\" DQUOTE ) ) DQUOTE
```

so it too is sugar over the character stream, not a lexer special case.  The
*decoding* of escapes (`\n` → newline) is an action, not a matching concern.

### 4.3 Types of token definition

A token definition can be written three ways, and all three compile to the
same thing — a scanner `scan(src, pos) -> (kind, len) | no-match`:

1. **BNF over characters.**  `int = ["-"] 1*DIGIT`, `money = 1*DIGIT "." 2DIGIT`.
   The general case; compiled to a scanner by the generator.
2. **An inline jet — a hand-written scanner, right in the schema.**  A token
   defined by a raw code block, interleaved with the rules:

       ipv4 = {
           size_t n = 0;
           while (n < len && isdigit(s[pos + n])) n++;
           if (n == 0 || n > 3) return 0;
           /* ... three more octets, then return the match length ... */
       }

   The block is target-language code, copied verbatim into the generated
   parser as the body of a `scan(s, pos, len)` function.  It lives next to the
   rule it implements rather than in a separate file — the fast path,
   byte-for-byte as fast as a hand-written `yylex`.
3. **A refinement.**  `u16 = int where (v <= 65535)`, `port = u16 where (v != 0)`.
   Reuses another token's scanner (jet *or* BNF) and applies a predicate.  This
   is the declarative form of OpenBSD's "lex a string, validate in the action",
   and it composes.

The lexer is generated by trying every token's scanner at each position and
keeping the longest match (ties break by declaration order) — maximal-munch,
the rule a human already assumes.  The parser, unchanged, matches token kinds.

A schema declares its jet language on the first non-comment line
(`language C|Rust|Zig|Ada`), and may carry a raw `{ ... }` *preamble* before
the rules and a raw `{ ... }` *epilogue* after them — yacc's prologue and
epilogue, interleaved with the grammar.  Both are emitted verbatim; a jet is
the per-token form of the same verbatim block.

### 4.4 Jets, and why they are safe

The word "jet" is borrowed deliberately: a jet is a hand-written implementation
of something that also has a *formal* definition, and the two must agree.  A
token can be given both a BNF definition (the executable spec) and a jet (the
optimization):

```
ipv4 = 1*3DIGIT 3("." 1*3DIGIT)          ; spec — the executable definition
ipv4 = { ...hand-written scanner... }   ; jet — the fast path
```

The generator — or a test harness — cross-checks them over a corpus, turning
the classic jet failure mode (a hand-written scanner drifting from its spec)
into a check instead of a silent bug.  This is what makes hand-writing a
scanner for a hot token acceptable: the spec stays in the schema, and the
optimization is verifiable.

The IPv6 jet is the worked example.  Its fallback is one readable line:

    ; ipv6 — 1*4hexdig *( ":" 1*4hexdig ), with "::" allowed
    ipv6 = { …hand-written scanner… }

A first cut wrote the scanner as "hex digits and colons, either one" — which
looks right but over-matches: `em0`, `from`, and `beef` are bare words that
begin with a hex letter, and a scanner that accepts a lone hex letter splits
`em0` into `e` + `m0`, breaking every `a`–`f` keyword and interface name.  The
fallback is what surfaced the bug: the spec plainly requires a colon, so a jet
that matches a colon-less bare word is *visibly* wrong, and the fix falls out
of the spec directly — require a colon (`colons > 0`).  That is the point of
keeping the fallback in grammar rather than in a prose comment or in the
scanner's own head: "does the jet match its spec?" becomes a question answered
by reading one line of hbnf beside the jet, not by re-deriving a hand-written
C loop.  Jet and fallback sit adjacent in the schema, so any drift between
them is the bug, found at the schema before it reaches a mis-parsed config.

An inline jet is written in one target language, so it names its backend — or
sits beside the BNF spec, which the other backends compile.  A schema
meant for more than one language can carry per-language blocks, but the
recommended style is a BNF spec plus at most one hand-tuned jet for the
backend that actually gets deployed.

### 4.5 Why this does not cost speed

The worry with character-level parsing is that it means one token per character
and one heap allocation per character.  It does not have to.  The scanner
contract is `(kind, len)` over a source slice, not a pile of per-character
tokens; a run-level scanner (a bareword, a number) is emitted as a tight loop
over the slice, and only the *result* is materialized.  The measured baseline
(§6) is a token-level parser that already does per-token allocation and still
parses a million rules a second; the character-level form with run-level
scanners removes, not adds, allocation.  Jets exist for the cases where a
hand-written loop genuinely beats a generated one — the same reason OpenBSD's
hand-written `yylex` beats a table-driven flex lexer.

### 4.6 From slice to value

Matching a span of text is only half the job: the slice still has to become a
typed value, and the two steps stay separate.  The scanner (the lexer, or a
jet) classifies a span and returns `(kind, length)`; it never looks at the
value.  The parser matches those kinds to build the tree.  Only then does a
per-type *converter* turn a slice's characters into a value, and it always
receives the slice **whole**, as one contiguous string — never re-tokenized:

    port  = u16   ->  (uint16_t) strtoull(slice, NULL, 10)
    count = int   ->  atoll(slice)
    rate  = float ->  strtod(slice, NULL)
    name  = str   ->  the slice itself (copied, or a zero-copy reference)
    flag  = flag  ->  strcmp(slice, "yes") == 0 || ...

Structs and enums are not converted — they are *built*.  A struct is the
parser recursing over sub-rules and filling fields, each leaf converted by its
own converter; an enum maps a literal alternation to a tag.  The same split
holds inside a jet: its `{ }` block is a scanner, its value is the slice's
text unless it declares a converter of its own — classify with a scanner,
interpret with a converter, in both cases over one whole slice.

### 4.7 Binary wire: the same idea over octets

The lexer's unit is a code point because configuration is text.  A binary
protocol is the same problem one level down: the unit is an **octet**, and a
"token" is a fixed-width field reader instead of a character class.  A schema
declares `binary` (octet stream, network byte order); a field is `name:N`, C's
bitfield spelling with N in **bits**, packed the way a reader of the RFCs
expects: left to right as written, first field in the most significant
bits, big-endian, adjacent sub-byte fields coalescing into octets.
Read top to bottom, matching the RFC's packet diagram:

    binary

    ; Ethernet II (RFC 894) — 6 + 6 + 2 octets
    ethernet   = dst:48 src:48 ethertype:16 payload:*u8
    ethertype  = 0x0800 / 0x0806 / 0x86DD      ; IPv4 · ARP · IPv6

    ; ARP (RFC 826) — pure fixed-width (Ethernet + IPv4 case)
    arp = htype:16 ptype:16 hlen:8 plen:8 oper:16
          sha:48 spa:32 tha:48 tpa:32

    ; IPv4 (RFC 791) — one 32-bit word per line
    ipv4 = version:4 ihl:4 tos:8 total_length:16
           identification:16 flags:3 frag_offset:13
           ttl:8 protocol:8 header_checksum:16
           src:32
           dst:32
           options:*u8 payload:*u8

    ; TCP (RFC 793) — RFC 3168 (CWR/ECE) and RFC 3540 (NS) take three reserved bits
    tcp = src_port:16 dst_port:16 seq_num:32 ack_num:32
          data_offset:4 reserved:6
          urg:1 ack:1 psh:1 rst:1 syn:1 fin:1
          window_size:16
          checksum:16 urgent_pointer:16 options:*u8 payload:*u8

    udp = src_port:16 dst_port:16 length:16 checksum:16 payload:*u8

C bitfields are layout-undefined, so no C struct is emitted; the emitter
generates the shift-and-mask the daemons hand-write (`vihl >> 4`,
`vihl & 0x0F`), portable across compilers and byte orders.  A `name:N` field is
layout only — §4.6's converter turns its bits into a value: `src:32` renders
dotted-quad, `dst:48` six octets (spelled `dst:[6]` when octets read better).
The demos leave open length-bounded payloads (`total_length − ihl·4` octets, not
"the rest"), tag dispatch on a field value (EtherType choosing the payload
type), and checksums — the three gaps any binary protocol engine must close.
Binary mode is design, not yet implemented.

## 5. Implementation

### 5.1 The allocation storm

The first implementation lesson is about memory.  The unoptimized generated parser
materializes every token as a heap string (`lex_dup` in the lexer) and then,
for every string- or number-valued field, copies the token's text into the
result tree (`strdup`).  For a 100k-rule ruleset that is on the order of two
million `malloc`s and two million copies of short strings — and the benchmark
in §6 shows the cost plainly: 127 MB of peak RSS, about 1.25 KB per rule,
nearly all of it these transient copies rather than the result tree itself.

The fix is to stop allocating per token.  A token becomes a zero-copy slice —
`(kind, offset, length)` into the source buffer — so lexing allocates nothing
per token, and the character-level matching of §4 reads characters *inside* a
run's slice rather than from per-character tokens.  This is precisely why
"character-level" need not mean "one heap token per character": the character
stream is the source slice that a run-level scanner points at, not a pile of
allocated tokens.  The result tree still needs its own storage, but that can be
an arena, allocated once and freed once, instead of a `strdup` per field.

The measured baseline deliberately keeps the per-token copies, so the
number in §6 is the *before* picture against which the zero-copy and arena
changes are measured.

### 5.2 UTF-8 in, UTF-8 out

The second lesson is about text.  A configuration file is bytes on disk but
characters to a human; an ASCII-only parser treats a multi-byte UTF-8 sequence
as three unrelated bytes, so `"café"` in a comment or literal is mangled on the
way through.  hbnf treats the schema and the config as UTF-8 end to end: the
input is decoded to code points on the way in, the matcher operates on code
points, and the emitted parser writes UTF-8 on the way out.  A literal can name
a non-ASCII character, and a comment can contain one, because the lexer's unit
is a code point, not a byte.

This is the same move as §4, seen from the encoding side: making the character
stream the unit of matching is what makes UTF-8 free.  A scanner may still
fast-path ASCII — compare one byte at a time and fall back to the code-point
path only on a non-ASCII byte — so the common case costs nothing.

### 5.3 Backends and the FFI story

hbnf is written in Ada (the project it lives in, `ada-on-alpine`,
is an Alpine Linux aports overlay for the Ada/GNAT toolchain; the end goal is
the Ada Language Server).  `hbnf` is the front end: it parses a schema and
hands a typed rule tree to one of four emitters (`hbnf_c`, `hbnf_rust`,
`hbnf_zig`, `hbnf_ada`).  The emitters are structured identically: a type
analysis pass classifies each rule (scalar, enum, struct, list), then emits
declarations, `parse_<rule>` functions, and the lexer.  The emitted lexer is a
template parameterized by the schema's token definitions, not a fixed body.

The C backend is the reference and the one used for the FFI story: a shared
library `libhbnfconf` exposes `parse_config`, `conf_ptr`, and the error
handler, and thin bindings wrap it for Python (ctypes), Ruby (Fiddle), Perl
(FFI::Platypus), and newLISP (`import`).  Dynamic languages use the C backend
rather than a native reimplementation, which keeps the fast path single and the
bindings trivial.

## 6. Evaluation

The motivating question is whether a generated parser can load a firewall
ruleset of the size OpenBSD operators actually deploy.  The evaluation
measures the generated C parser on a synthetic pf-style config.

**Setup.**  A schema with the shape of a pf rule — action (`pass`/`block`/
`match`), direction (`in`/`out`), interface, protocol, and a `from`/`to` pair
of address-plus-port — and a generator that emits 100,000 rules (8.46 MB) with
a realistic mix of keywords, dotted addresses, and port numbers.  The parser is
compiled with GCC at `-O2`; timing is wall-clock around a single `parse_text`
call; peak RSS is `getrusage`'s `ru_maxrss`.

| N | bytes | time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| 100,000 | 8.46 MB | 72.7 ms | 1.38 M | 111 | 127 MB |
| 1,000,000 | 84.6 MB | 0.72 s | 1.39 M | 117 | 1.24 GB |

Throughput is linear in the rule count, at roughly 1.4 million rules per second
and ~120 MB/s, with memory at about 1.25 KB per rule — dominated by the
per-token and per-field string copies that §5 flags as the baseline.  The
100k-rule case completes in under 75 ms, well inside the "load a big ruleset
fast" criterion that motivated the work.

The toy schema is a minimal shape, so those numbers understate the real cost.
Measured the same way against the shipped `grammars/pfctl.hbnf` — the full
grammar, with its 36-way filter-option alternation and address/port/IP parsing
rather than the toy's five fields — the generated parser takes longer and holds
more, as a reviewer who runs the motivating workload would find:

| N | bytes | time | rules/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| 100,000 | 4.48 MB | 310 ms | 322 K | 14.5 | 310 MB |
| 1,000,000 | 44.8 MB | 3.36 s | 297 K | 13.3 | 3.01 GB |

The real grammar is about four times slower per rule and holds two-and-a-half
times the memory: the toy schema's five-field rule simply does far less work per
token.  Both ratios are what the rest of §5 is spent on — the filter-option
dispatch (§5.2's FIRST-set switch) took the full grammar from 0.70 s down to
310 ms, and the string arena (§5.3) accounts for most of the remaining RSS.
This is the honest number for the "load a big firewall ruleset" criterion: a
100k-rule `pf.conf` parses in about 310 ms at 310 MB, and a 1M-rule one in 3.4 s
at 3 GB.

**Compactness.**  The same notation compresses a real grammar.  OpenBSD's
`httpd.conf` is 2,785 lines of parse.y — 63 rules and 79 keyword tokens — most
of it action code and keyword-table plumbing.  The hbnf schema for the same
language is under two hundred lines; the shape survives (blocks, server options,
TLS, fastcgi, logging, MIME types) and the `{ ... }` actions are gone because
they were, for config, bookkeeping the binder does automatically.

Across the nine daemon grammars with schemas, the win is aggregate, not
anecdotal: 25,794 lines of hand-written `parse.y` — lexer, grammar, and action
code together — collapse to 2,255 lines of schema, a 91% reduction, and the
ratio holds on every daemon at a factor of roughly ten to twenty:

| daemon | parse.y (lines) | hbnf (lines) |
|---|---:|---:|
| bgpd | 6,146 | 544 |
| dhcpleased | 863 | 53 |
| httpd | 2,785 | 193 |
| ldpd | 1,739 | 154 |
| ntpd | 841 | 82 |
| pfctl | 6,546 | 569 |
| relayd | 3,800 | 382 |
| snmpd | 2,099 | 173 |
| unwind | 975 | 105 |
| **total** | **25,794** | **2,255** |

**Status.**  The measured baseline is the token-level parser with per-token
allocation (§5.1) — deliberately the unoptimized version.  The inline-jet mechanism
(§4.3–4.4), the `language` declaration, the preamble/epilogue blocks, and the
id-ref serializer and rebuild side (§3.4) are implemented in the C backend: the
schema parses them, the C emitter produces a working parser, a jet that
recognizes IPv4 addresses round-trips through the generator, and the nine
OpenBSD daemon schemas compile through all four emitters (the e2e suite and the
52-check conformance suite pass).  The character-level grammar (§4.1), the
zero-copy/arena token representation (§5.1), the UTF-8 code-point path (§5.2),
and the Rust/Zig/Ada jet emission are the remaining increments.  The baseline
is reported to establish what the design is being compared against, and because
it already meets the performance criterion.

## 7. Related work

**yacc/bison and lex/flex.**  The default answer, and the thing this work
departs from.  The split is principled (§2.2) but forces the token boundary to
be a lexer-level decision, which is exactly where the domain hacks accumulate.

hbnf deliberately gives up four things yacc has, and each is a trade, not an
oversight.  *Left recursion* (`list : list item | item`) is how yacc expresses
repetition; hbnf's recursive-descent emitters cannot descend into it, so a
schema spells the same thing as `*( item )` — a restructuring, not a loss of
power.  *Semantic actions* — arbitrary C between rule symbols, run as the
parser reduces, with `$1`/`$2` access to sub-values — are the reason yacc is a
"compiler-compiler".  hbnf keeps a narrower form: an action jet is C attached
to a rule and run once per node in a bottom-up walk after the whole parse has
succeeded, so backtracking never re-runs a side effect and no action can steer
the parse.  A grammar without actions still yields a typed tree in all four
languages; a daemon binding adds actions only to build the daemon's own
structures, which is what a drop-in for its `parse.y` has to do.  *Lexer start
conditions* (`%x STRING`) let one lexer re-tokenize the same bytes by parser
state; hbnf's jets are stateless per token kind.  *Precedence declarations* (`%left`/`%right`) resolve expression
ambiguity declaratively; hbnf resolves it structurally with ordered choice.
None of these is beyond reach (§8), but a config schema needs none of them, and
their absence is what keeps the notation small.

**Parsing expression grammars.**  PEG (Ford) removes the token split in the
other direction — ordered choice over characters — at the cost of ordered
choice's surprise (a later alternative is unreachable) and worst-case
backtracking.  hbnf keeps ABNF's maximal-munch lexer and LL(1)-ish grammar,
which is the property that keeps the 100k-rule parse linear.

**Scannerless parsing.**  SDF and the Stratego/XT family parse without a
separate scanner, resolving ambiguity by disambiguation rules rather than by
choice order.  hbnf is scannerless in the same sense but keeps the lexer as a
*generated* maximal-munch stage; the token definitions, not a fixed lexer,
determine what a token is.

**Tree-sitter and pest.**  Both are modern, incremental, error-tolerant parser
generators.  They are general parsers; hbnf's niche is the narrower and
higher-volume one of configuration, where self-contained single-file output,
typed trees, and the `parse_config` shape matter more than incrementality.

**Jets.**  "Jet" is hbnf's term for a hand-written implementation of a formally
specified operation, kept in agreement with its spec.  Hand-optimizing a hot
path while a declarative spec stays the source of truth is an old idea in
systems — a native method for a bytecode, an intrinsic for a library routine —
and hbnf applies it one level down, to lexing: a token's BNF definition is the
spec, the hand-written scanner is the jet, and the agreement check is the
safety property that makes hand-optimizing a hot token acceptable.

## 8. Conclusion and future research

This paper has described hbnf, a parser generator whose schema is an extension of
ABNF, whose generated lexer is a thin character stream, and whose token
definitions live in the grammar — as BNF, as hand-written jets, or as
refinements of either.  The baseline already parses a 100k-rule firewall
ruleset in 75 ms, and the grammar notation compresses a 2,785-line yacc
grammar to under two hundred lines.

Near-term work is to finish the implemented surface — the jet and refinement
syntax across the four emitters, the spec-vs-jet cross-check, the zero-copy or
arena token representation — and to re-measure against the baseline in §6.

Two research directions follow from the design.

**A grammar library, with includes and overrides.**  The nine OpenBSD schemas
already repeat the same boilerplate — `string = str / word`, `yesno =
"yes" / "no"`, IPv4/IPv6 and port handling — so a schema should be able to
`include "stdlib.hbnf"` and override individual definitions locally.  yacc has
no grammar-level include at all (its only `#include` reaches the verbatim C
blocks, not the rules), so this is hbnf exceeding yacc rather than matching it;
a token override and a rule override become the same operation, since a token
*is* a rule.  The open question is the override semantics — local-shadows-
include, last-definition-wins, or an explicit `override` — and how a
cross-checked jet from a library behaves when a program overrides only its
fallback.

**From recognizer to compiler-compiler.**  A "compiler-compiler" is a
recognizer plus a way to write passes over the tree it produces, and every pass
in a compiler frontend is one of two shapes.  An *analysis* walks the tree and
computes without changing it — name resolution fills a symbol table, type
checking computes types and records diagnostics, linting collects warnings —
and this is exactly a *visitor*: for each composite rule hbnf emits a
`visit_<rule>` that calls a hook on every node and then recurses into its
fields, so the user writes only "on a server node, bind its name" and never the
traversal itself.  A *transformation* rebuilds the tree bottom-up — desugaring
replaces `a > b` with a canonical form, lowering maps high-level constructs to
low-level ones, optimization rewrites subtrees — and this is exactly a
*fold/map*: hbnf emits a `map_<rule>` that recurses first and then hands the
node to a hook, so the user writes only "replace a server node with its lowered
form".  Code generation is then a final visitor over the fully-transformed
tree.  The parser (given) plus visit, map, and serialize (generated) are thus
the complete set of primitives a compiler needs — analysis, transformation, and
emission are one recursion over one typed tree, and the serialize walk of §3.4
is the wire-form analogue of the daemons' `config_set*` serialization — and
because a pass is an ordinary function
of the target language — not a `$1`/`$2` action embedded in the grammar — the
one-grammar, four-language property survives: the same schema emits the
traversal in the C, Rust, and Zig backends, and a pass is written once per
target language, not once per grammar.  The visitor/fold route is what makes hbnf a true
compiler-compiler without reintroducing the semantic-action layer that would
re-tie a grammar to one backend.  Reclaiming the remaining yacc facilities —
left recursion (via an Earley or GLR kernel) and operator-precedence
declarations — is a further step in the same direction.

## References

[1] D. Crocker and P. Overell, "Augmented BNF for Syntax Specifications: ABNF,"
    RFC 5234, 2008.
[2] S. C. Johnson, "Yacc: Yet Another Compiler-Compiler," 1975.
[3] M. E. Lesk and E. Schmidt, "Lex — A Lexical Analyzer Generator," 1975.
[4] B. Ford, "Parsing Expression Grammars: A Recognition-Based Syntactic
    Foundation," POPL 2004.
[5] E. Visser, "Scannerless Generalized-LR Parsing," 1997.
[6] OpenBSD, usr.sbin/httpd/parse.y and related, <https://cvsweb.openbsd.org>.
