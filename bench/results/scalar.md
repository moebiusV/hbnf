**Numbers**, nanoseconds each (best of three runs; the same text for each tool):

| numbers | hbnf_scalar.h | fast_float | glibc strtod |
|---|---:|---:|---:|
| the document's integers (4.7 digits) | 6.1 ns | 5.3 ns | 11.5 ns |
| the document's decimals (like 308.248) | 8.1 ns | 8.0 ns | 44.8 ns |
| 17-digit decimals, 1e-5 to 1e11 | 21.7 ns | 21.0 ns | 74.1 ns |
| 17-digit doubles of every magnitude | 19.2 ns | 22.0 ns | 130.5 ns |

**Strings**, GB/s of input (one 64 KiB string):

| string | hbnf_unescape | a byte loop |
|---|---:|---:|
| a string with no escape | 26.1 GB/s | 2.4 GB/s |
| an escape in 32 bytes | 7.9 GB/s | 2.3 GB/s |
| an escape in 8 bytes | 2.6 GB/s | 2.6 GB/s |

_2026-10-29; gcc -O2, glibc; fast_float v6.1.6; hbnf 36d3334.  The integers go through `strtoll` in the last column.  fast_float reads an integer as a `long long`, and a decimal as a `double`._
