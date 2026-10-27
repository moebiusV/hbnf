| language | notation | rules | lines | symbols | characters |
|---|---|---:|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 108 | 116 | 1246 | 8064 |
| | HyperBNF (`corpus/algol60`) | 47 | 72 | 528 | 3604 |
| | **saved** | **56%** | **38%** | **58%** | **55%** |
| JSON | RFC 8259's ABNF | 30 | 45 | 193 | 949 |
| | HyperBNF (`corpus/json`) | 17 | 17 | 138 | 641 |
| | **saved** | **43%** | **62%** | **28%** | **32%** |
| TOML 1.0 | TOML's ABNF (toml.abnf) | 124 | 126 | 666 | 4646 |
| | HyperBNF (`corpus/toml`) | 46 | 49 | 599 | 2599 |
| | **saved** | **63%** | **61%** | **10%** | **44%** |
| C | 32V's cgram.y (mip), 1979 | 55 | 386 | 813 | 3755 |
| | HyperBNF (`corpus/c/c79.hbnf`) | 62 | 74 | 674 | 5155 |
| | **saved** | **-12%** | **81%** | **17%** | **-36%** |
| | HyperBNF with its token rules (`corpus/c/c79-words.hbnf` too) | 91 | 106 | 988 | 6649 |
|  | PCC's cgram.y (NetBSD trunk) | 84 | 368 | 1029 | 6505 |
| | HyperBNF (`corpus/c/pcc99.hbnf`) | 94 | 121 | 1087 | 8628 |
| | **saved** | **-11%** | **67%** | **-5%** | **-32%** |
| | HyperBNF with its token rules (`corpus/c/pcc99-words.hbnf` too) | 133 | 169 | 1542 | 11033 |
|  | GCC 4.0.4's c-parse.in (C part) | 172 | 892 | 1930 | 18966 |
| | HyperBNF (`corpus/c/gnu99.hbnf`) | 93 | 133 | 1124 | 8992 |
| | **saved** | **46%** | **85%** | **42%** | **53%** |
| | HyperBNF with its token rules (`corpus/c/gnu99-words.hbnf` too) | 132 | 182 | 1583 | 11454 |
| YAML 1.2 | the YAML 1.2.2 spec's productions | 201 | 861 | 1350 | 13273 |
| | HyperBNF (`corpus/yaml`) | 94 | 104 | 1387 | 6057 |
| | **saved** | **53%** | **88%** | **-2%** | **54%** |
