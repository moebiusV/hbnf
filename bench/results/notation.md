| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | HyperBNF (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | HyperBNF (`corpus/json`) | 17 | 17 | 138 | 641 |
| | **saved** | **43%** | **62%** | **28%** | **32%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/json/json-tape.hbnf`) | 17 | 22 | 158 | 743 |
| | the same with the C it carries (the tags, the emits) | 17 | 28 | 243 | 1312 |
| | the tape both tape grammars share (`runtime/hbnf_tape.h`) | 0 | 56 | 228 | 1349 |
| TOML 1.0 | TOML's ABNF (toml.abnf) | 124 | 126 | 666 | 4646 |
| | HyperBNF (`corpus/toml`) | 45 | 49 | 600 | 2604 |
| | **saved** | **64%** | **61%** | **10%** | **44%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/toml/toml-tape.hbnf`) | 45 | 57 | 635 | 2775 |
| | the same with the C it carries (the tags, the emits) | 45 | 63 | 807 | 3890 |
| C | 32V's cgram.y (mip), 1979 | 55 | 386 | 813 | 3755 |
| | HyperBNF (`corpus/c/c79.hbnf`) | 62 | 74 | 674 | 5155 |
| | **saved** | **-12%** | **81%** | **17%** | **-36%** |
| | HyperBNF with its token rules (`corpus/c/c79-words.hbnf` too) | 91 | 106 | 988 | 6649 |
|  | PCC's cgram.y (NetBSD trunk) | 84 | 368 | 1029 | 6505 |
| | HyperBNF (`corpus/c/pcc99.hbnf`) | 92 | 119 | 1074 | 8513 |
| | **saved** | **-9%** | **68%** | **-3%** | **-30%** |
| | HyperBNF with its token rules (`corpus/c/pcc99-words.hbnf` too) | 131 | 167 | 1529 | 10918 |
|  | GCC 4.0.4's c-parse.in (C part) | 172 | 892 | 1930 | 18966 |
| | HyperBNF (`corpus/c/gnu99.hbnf`) | 91 | 131 | 1111 | 8885 |
| | **saved** | **47%** | **85%** | **42%** | **53%** |
| | HyperBNF with its token rules (`corpus/c/gnu99-words.hbnf` too) | 130 | 180 | 1570 | 11347 |
| YAML 1.2 | the YAML 1.2.2 spec's productions | 201 | 861 | 1350 | 13273 |
| | HyperBNF (`corpus/yaml`) | 94 | 109 | 1423 | 6251 |
| | **saved** | **53%** | **87%** | **-4%** | **53%** |
| | HyperBNF with `%emit`, onto a tape (`corpus/yaml/yaml-tape.hbnf`) | 97 | 120 | 1594 | 7071 |
| | the same with the C it carries (the tags, the emits) | 97 | 127 | 1998 | 9880 |
