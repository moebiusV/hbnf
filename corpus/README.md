# corpus/

Real text that hbnf is meant to be able to read, each in a directory of its own with
its source, its licence and attribution, hashes where the files are copies, and a
README that says what is in it and what state it is in.

| directory | what | state |
|---|---|---|
| `rfc/` | grammar snippets lifted from RFCs, with vectors that must and must not parse | in use (`tests/rfc.sh`) |
| `posix/` | the POSIX shell grammar | paused |
| `imp72/` | the IMP72 compiler's sources (DECUS 10-198) | paused |
| `algol60/` | the Revised Report on ALGOL 60, its BNF, and a grammar in hbnf | in use (`tests/algol60.sh`) |
| `algol68/` | the Revised Report's W-grammar (planned, before C++) | not started |
| `bip39/` | the ten official BIP-39 word lists | in use (`tests/wire.sh`) |

Planned, as the wire layer and the daemon grammars gain their own: `ipv4/`, `arp/`,
`ipv6/`, `icmp/`, `obconf/`.  Their grammars exist today in other places:
`tests/wire/net.hbnf` (Ethernet, ARP, IPv4, IPv6, TCP, UDP, one file because
a binary grammar cannot `include` another yet), `tests/wire/segwit.hbnf` and
`tests/wire/mnemonic.hbnf`, and `grammars/obconf_*.hbnf` with the configs under
`tests/daemons/`.  Each moves here when it has its RFC text, its vectors and its README.
