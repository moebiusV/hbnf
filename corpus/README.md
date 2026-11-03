# corpus/

Real text that hbnf is meant to be able to read, each in a directory of its own with
its source, its licence and attribution, hashes where the files are copies, and a
README that says what is in it and what state it is in.

| directory | what | state |
|---|---|---|
| `rfc/` | grammar snippets lifted from RFCs, with vectors that must and must not parse | in use (`tests/rfc.sh`) |
| `posix/` | the POSIX shell grammar (POSIX.1 §2.10), the standard's own text plus tokens and ordering | in use (`tests/posix.sh`; `scripts/posix-scan.sh` against dash) |
| `c/` | six grammars: C of UNIX/32V (`c79`), ISO C90 (`c89`), C99 (`c99`), the C that PCC reads (`pcc99`), C99 with the GNU extensions of GCC 4.0.4 (`gnu99`), and C11 (ISO 9899:2011 Annex A) with the GNU forms headers use (`c11`), the start of a small C compiler | in use (`tests/c.sh`, `tests/c79.sh`, `tests/c89.sh`, `tests/c99.sh`, `tests/pcc99.sh`, `tests/gnu99.sh`, `tests/sqlite.sh`; `scripts/c-scan.sh` against gcc; `bench/cspeed.sh`) |
| `imp72/` | the IMP72 compiler's sources (DECUS 10-198) | cancelled: IMP72 gets its own compiler; the files stay as the subject of `METACOMPILERS.md` |
| `algol60/` | the Revised Report on ALGOL 60, its BNF, and a grammar in HyperBNF | in use (`tests/algol60.sh`) |
| `json/` | RFC 8259 in HyperBNF, checked against Python's `json` on 80,000 texts; a tape grammar (`json-tape.hbnf`) | in use (`tests/json-diff.sh`, `tests/emit.sh`) |
| `toml/` | TOML 1.0, checked against the toml-test suite and Python's `tomllib`; a tape grammar (`toml-tape.hbnf`) | in use (`tests/toml.sh`, `tests/toml-diff.sh`, `tests/emit.sh`) |
| `yaml/` | YAML 1.2, indentation as a number the parser works out; the YAML test suite and PyYAML; a tape grammar (`yaml-tape.hbnf`) | in use (`tests/yaml.sh`, `tests/yaml-suite.sh`, `tests/yaml-diff.sh`, `tests/emit.sh`) |
| `graphql/` | GraphQL (October 2021): the executable language, the type system and its extensions, in 54 rules against the specification's 99 productions; checked by the specification's examples in four backends and against a second scanner of its lexical grammar | in use (`tests/graphql.sh`, `tests/graphql-diff.sh`) |
| `html/` | HTML (WHATWG 13.1, the syntax of a conforming document): omissible tags, void and raw-text elements, svg/math with CDATA; `<script>` read by another grammar as an island; checked against html5lib's strict parser | in use (`tests/html.sh`, `tests/html-diff.sh`) |
| `js/` | JavaScript (ECMAScript 2023): the Script and Module goals in 151 rules against the specification's 303 productions, automatic semicolon insertion and the restricted productions with `eol`, the cover grammars by ordered choice; checked in four backends, by the test262 parser tests and against V8 on 6,000 random programs and every code point as a name | in use (`tests/js.sh`, `tests/js-diff.sh`, `tests/js262.sh`) |
| `mustache/` | Mustache templates, with a closing tag that repeats the opening one; checked against chevron on 12,000 texts | in use (`tests/mustache-diff.sh`) |
| `cobol/` | COBOL in free format: the four divisions, the data description clauses and 30-odd statements, checked against GnuCOBOL's `cobc` | begun (`tests/cobol.sh`); fixed format, `COPY` and the rest are not read yet |
| `sgml/` | SGML (ISO 8879): the document type declaration and its declarations, the SGML declaration, the instance at the level of markup; HTML 4.01 Strict, DocBook and TEI style DTDs; no SGML parser to check against | begun (`tests/sgml.sh`); what needs the DTD (omitted tags, short references, a changed syntax) is not read |
| `algol68/` | the Revised Report's W-grammar | not started; on the list (`RFCPLAN.md` step 20), with C++ |
| `bech32/` | the bech32 and bech32m reference implementation (BIP-173, BIP-350) | saved; the segwit grammar of `tests/wire/segwit.hbnf` does not call it yet (`tests/wire.sh`) |
| `bip39/` | the ten official BIP-39 word lists | in use (`tests/wire.sh`) |

Planned, as the wire layer and the daemon grammars gain their own: `ipv4/`, `arp/`,
`ipv6/`, `icmp/`, `obconf/`.  Their grammars exist today in other places:
`tests/wire/net.hbnf` (Ethernet, ARP, IPv4, IPv6, TCP, UDP, one file because
a binary grammar cannot `include` another yet), `tests/wire/segwit.hbnf` and
`tests/wire/mnemonic.hbnf`, and `grammars/obconf_*.hbnf` with the configs under
`tests/daemons/`.  Each moves here when it has its RFC text, its vectors and its README.
