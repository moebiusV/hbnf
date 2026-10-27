| language | notation | characters | o200k_base tokens | Qwen2.5 tokens |
|---|---|---:|---:|---:|
| ALGOL 60 | the Report's BNF | 8064 | 2290 | 2269 |
| | HyperBNF | 3604 | 890 | 870 |
| | **saved** | **55%** | **61%** | **62%** |
| JSON | RFC 8259's ABNF | 949 | 379 | 407 |
| | HyperBNF | 641 | 247 | 260 |
| | **saved** | **32%** | **35%** | **36%** |
| TOML 1.0 | TOML's ABNF | 4646 | 1564 | 1625 |
| | HyperBNF | 2599 | 1130 | 1193 |
| | **saved** | **44%** | **28%** | **27%** |
| C | 32V's cgram.y, 1979 | 3755 | 1593 | 1566 |
| | HyperBNF | 5155 | 1187 | 1157 |
| | **saved** | **-36%** | **25%** | **26%** |
| | HyperBNF with its token rules | 6649 | 1754 | 1735 |
|  | PCC's cgram.y, C99 | 6505 | 2295 | 2248 |
| | HyperBNF | 6171 | 1444 | 1411 |
| | **saved** | **5%** | **37%** | **37%** |
|  | GCC 4.0.4's c-parse.in, C99 | 18966 | 6050 | 5918 |
| | HyperBNF | 6171 | 1444 | 1411 |
| | **saved** | **67%** | **76%** | **76%** |
| | HyperBNF with its token rules | 7923 | 2129 | 2113 |
| YAML 1.2 | the spec's productions | 13273 | 4927 | 4912 |
| | HyperBNF | 6057 | 2642 | 2690 |
| | **saved** | **54%** | **46%** | **45%** |

_The text is the grammar as `notation.sh` counts it.  o200k_base is OpenAI's tokenizer (tiktoken 0.14.0) and Qwen2.5's is an open-weights model's (tokenizers 0.23.3); Claude's tokenizer is not public, so its count was not measured._
