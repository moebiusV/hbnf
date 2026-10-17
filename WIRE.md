# The wire layer: octets, bit fields and enum numbers

A grammar that says `binary` describes bytes, not text.  The same notation that
reads a configuration file reads an Ethernet frame, and the generated parser
takes a buffer.  This is `RFCPLAN.md` step 7b.  **Status:** the C backend reads
and writes it (the generating direction exists too); Rust, Zig and Ada are next.
Enum numbers (`"icmp"@1`) work in all four backends already.

    binary

    ; IPv4 (RFC 791): one 32-bit word to a line.
    ipv4 = version@0:4 ihl:4 tos:8 total_length:16
           identification:16 flags:3 frag_offset:13
           ttl:8 protocol:8 header_checksum:16
           src:32
           dst:32
           options:[ihl*4 - 20]
           payload:( ?(protocol == 6) t:tcp | ?(protocol == 17) u:udp | rest:*u8 )

The files `tests/wire/net.hbnf` (Ethernet, ARP, IPv4, IPv6, TCP, UDP) and
`tests/wire.sh` (byte fixtures for each, read and written back) are the worked
examples.  So is `tests/wire/segwit.hbnf`, the data part of a bech32 address
(BIP-173, BIP-350): 5-bit symbols, a witness program whose octets start inside
an octet, padding that must be zero, and rules on the program's length:

    segwit = version:5 ?(version <= 16)
             program:[(remaining - 30) / 8]
             ?(len(program) >= 2 && len(program) <= 40)
             ?(version != 0 || len(program) == 20 || len(program) == 32)
             ?(remaining - 30 < 5) pad:bits(remaining - 30) ?(pad == 0)
             checksum:30

It reads the five published valid addresses to their version and program, and
refuses six made to break one rule each.  The checksum is read, not yet checked
(see the end of this page).

## Why these two characters

| char | means | precedent |
|---|---|---|
| `:` | a width: `ttl:8` is 8 bits | C's bit-field (`unsigned ttl : 8`), Erlang's bit syntax (`<<Ttl:8>>`); and, at the start of a rule, the definition: Forth's `: name ... ;` and the label in assembly |
| `@` | a place: `version@0:4` is 4 bits starting at bit 0 | "at": Ada's representation clause (`F at 0 range 3 .. 7`); BLISS and IMP72 give position and size together (`A<p,s>`) |

Both count from zero, as C and IMP72 do (IMP72's arrays start at zero and its
bit fields `A<B,C>` count from the right).  The direction follows the RFCs, not
IMP72 or the hardware manuals: bit 0 is the most significant bit, the leftmost
in a packet diagram.

They never clash.  A rule's `:` is the first `:` after a name in column 1 (a
rule's continuation lines are indented), and every other `:` is a width glued
to the name before it.  `@` also numbers an enum literal (below), where "at"
means the same thing: *at this value*.

## A field

| write | meaning |
|---|---|
| `name:N` | N bits, 1 to 64.  The first field is in the most significant bits, the way an RFC's packet diagram reads; fields that do not fill an octet share it |
| `name:16le`, `name:8s`, `name:32sle` | little-endian (`le`; `be` is the default), signed (`s`).  Little-endian needs a whole number of octets |
| `name:u16`, `name:i32le` | the same, spelled as a type |
| `name@K:N` | N bits that **must** start at bit K of the record (bit 0 is the most significant bit of its first octet).  It writes nothing new; it checks the author's arithmetic against the RFC.  hbnf proves it when the fields before it are fixed, and the parser checks it when they are not |
| `name:[expr]` | `expr` octets: a slice of the input (a copy if they start inside an octet) |
| `name:*u8` | all the octets that are left |
| `name:bits(expr)` | `expr` bits (at most 64) |
| `0x0800`, `0b101` | a constant, as wide as its digits: `0x0800` is 16 bits, `0b101` is 3.  A decimal number has no width, and is refused with that reason |
| `name:rule` / `rule` | a nested record of that rule (a bare `rule` names the field `rule`) |
| `name:*rule`, `name:2*4 rule`, `name:(n)*rule` | any number, 2 to 4, exactly `n` records of that rule |
| `name:( a \| b \| c )` | one of several; the field has a `kind` (1, 2, 3) and the alternative's fields |
| `?(expr)` | a condition.  At the start of an alternative it is a **guard** (the alternative is taken only if it holds); between fields it is a **check** (the read fails if it does not).  `?(expr) "words"` is a check whose failure says those words |

A rule that is a list of constants (`ethertype = 0x0800 | 0x0806 | 0x86DD`) is a
**value set**.  A field named for it, or of its type, must be one of those
values: `ethertype:16`.

### Expressions

`expr` is C's integer arithmetic: `+ - * / % << >> & | ^ ~ !`, comparisons,
`&&` `||`, parentheses, decimal and `0x` numbers, over the fields read earlier
in the same record (`options:[ihl*4 - 20]`), `remaining`, the number of bits
left in the input, `len (field)`, the number of octets in a field read as
`name:[n]` or `name:*u8`, and `align`, the bits to the next unit boundary
(`units`, below; a message that ends in a partly filled unit says
`pad:bits(align)`).  Division by zero is 0, and a shift count is taken mod 64.
Using a name that is not a number read before that point is refused, with the
names that are.

### Names

Field and rule names are C identifiers.  A hyphen is refused with the underscore
to write instead (`total-length` reads as a subtraction), and so is a C keyword
(`int:8`).

## The C API

    bool parse_bits  (const uint8_t *buf, size_t nbits, T *out, char *err, size_t errsz, size_t *at);
    bool parse_bytes (const uint8_t *buf, size_t len,   T *out, char *err, size_t errsz, size_t *at);
    bool emit_bits   (const T *in, uint8_t *buf, size_t cap, size_t *nbits, char *err, size_t errsz);
    bool emit_bytes  (const T *in, uint8_t *buf, size_t cap, size_t *n,     char *err, size_t errsz);
    void free_arena  (void);

`T` is the first rule's type.  Reading uses the whole buffer or fails and says
where (`at` is the octet) and why (`ethernet.src: needs 48 bits, 32 left`).
Octets are slices of the input; the few that start inside an octet are copied
into an arena that `free_arena` releases.

Writing is the other direction, from the same grammar.  With `buf` NULL it only
counts; `*n` is always the size the message takes, so the usual call is twice.
A value that does not fit its field, a length that disagrees with the octets it
describes, a value outside a value set, or an alternative whose guard does not
hold is an error that names the field, not a silently wrong message.  A width
that depends on `remaining` cannot be written: a writer does not know the size of
a message it has not written.

## Text: a message written in units

Bytes are not the only way a message is written.  A bech32 address spells 5 bits
with each of 32 characters; a BIP-39 mnemonic spells 11 with each of 2048 words.
The text is a decoding of the bits, the way UTF-8 is a decoding of octets, and a
`units` line says how:

    units 5 bech32-symbol from "bech32.hbnf"
    units 11 bip39-word from "bip39/english.hbnf" separator bip39-space

`units W name from "file"` takes the enum rule `name` of a text grammar: each
literal is the spelling of one unit, and its **number** (its place in the list,
or `"x"@7`) is the unit's value, W bits wide.  `grammars/bech32.hbnf` is the 32
symbols; `grammars/bip39/` the ten word lists.  A `separator` is a rule that is
one literal, written between units (BIP-39's blank, or U+3000 in Japanese).

The C file then has two more functions:

    bool parse_text (const char *text, size_t len, T *out, char *err, size_t errsz, size_t *at);
    bool emit_text  (const T *in, char *buf, size_t cap, size_t *n, char *err, size_t errsz);

`parse_text` spells out the units (longest spelling first, and with a separator
only one that is followed by it or by the end, so `act` is never taken for the
start of `actor`), packs their values into bits, and reads those; `at` is the
character where it went wrong.  `emit_text` writes the bits and spells them.
The tests round-trip the five published segwit addresses and ten mnemonics, the
BIP-39 test vectors among them.

    binary
    units 11 bip39-word from "bip39/english.hbnf" separator bip39-space
    mnemonic = ?(remaining % 33 == 0 && remaining / 33 >= 4 && remaining / 33 <= 8)
                  "a mnemonic has 12, 15, 18, 21 or 24 words"
               entropy:[remaining / 33 * 4]
               ?(len(entropy) % 4 == 0)
               checksum:bits(len(entropy) / 4)
      %action{
          if (n->entropy.len != 16 && n->entropy.len != 32)
              HBNF_WARN("valid BIP-39, but wallets mostly make 12 and 24 words");
      }

reads `abandon ... about` as 16 octets of zeros and the checksum 3.  The checksum
is read, not yet checked: that, and computing it when writing, wait for
checksum functions and derived fields.

## Actions

`%action{ code }` at the end of a rule is C that runs on that rule's record, as
`n`, **after** the whole read has succeeded, children before parents.  It never
runs during the read, so an alternative that is tried and given up cannot have
run it (the same rule `%action` has in a text grammar).  Inside it:

- `n->field` are the typed fields (`n->entropy.len`, `n->payload.kind`).
- `HBNF_WARN ("text")` adds a warning to the result: `out->warnings[]`, a count
  in `out->nwarnings`, of the first rule's record.  A warning is about a message
  that is valid.
- `HBNF_FAIL ("text")` fails the read, naming the rule.  Use it for what a field
  must satisfy that an expression cannot say (a checksum, once it can be
  computed).

An action is the semantic member of the family; `%emit{ }`, the generative
member, is the one that will fill in a derived field (a checksum, a length)
when a tree is written, and is not built.  The warnings are collected in
static storage, so a parser that has actions is not reentrant.

## Enum numbers

A rule made only of literals is an enum.  Its values are 0, 1, 2 ... in the order
written; `"literal"@N` gives one its own number, as `NAME = N` does in C, and an
alternative without one is the one before plus 1:

    proto = "icmp"@1 | "tcp"@6 | "udp"@17 | "sctp"@0x84 | "other"

declares `icmp` 1, `tcp` 6, `udp` 17, `sctp` 132, `other` 133 in C, Rust, Zig and
Ada (an Ada representation clause, a Zig `enum(u8)`, a Rust discriminant).  The
numbers must fit 31 bits and be distinct.  Only a rule of plain literals can have
them.

A word list is an enum, and the number of a word is its place in the list.  When
the author writes words in a union (`"act" / "actor"`) hbnf matches the longer
word first, and **keeps the values in the order written**: the index of `actor` is
where the list has it.  That is what BIP-39 needs; `bip39-corpus/` holds the ten
official 2048-word lists as include files (`include "bip39/english.hbnf"`), and
`tests/wire.sh` reads every word of every list back to its line number.  A union
of plain words is a sort, not a search, so a 2048-word list takes a fifth of a
second.

## What is not built yet

- Rust, Zig and Ada backends for `binary` (C has it).
- **Units.**  A field's width is in bits and a string is an array of units, but
  a unit is not always a bit: an octet, a code point and a machine word (9-bit
  bytes, 36-bit words) are different things, and the notation should say which.
  The design: a number may carry a unit, `b` bits, `B` bytes, `c` code points,
  `W` words, and a file may say how big its byte and word are (`byte 9`,
  `word 36`).  `@Off:Len` is then a slice of any array of units, strings
  included: `name@4B:4B` is 4 bytes from byte 4, and `name@4:4` is 4 bits from
  bit 4.  Without a suffix the unit is the file's own (bits in a `binary` file).
- **Layout records.**  A record in which every field says where it is
  (`flags@0:3 id@3:13`) is a register layout, read in any order with gaps and
  overlaps.  Where only some do, `@` is the check described above.
- **Checksums** (SHA-256 for BIP-39, the BCH polynomial for bech32): checking
  one on reading can be an `%action` that calls `HBNF_FAIL`; computing one when
  writing, and a length field derived from its payload, need `%emit`.
