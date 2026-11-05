**Numbers**, nanoseconds each (best of three runs; the same text for each tool):

| numbers | hbnf_scalar.h | fast_float | glibc strtod |
|---|---:|---:|---:|
| the document's integers (4.7 digits) | 6.0 ns | 5.3 ns | 11.3 ns |
| the document's decimals (like 308.248) | 8.0 ns | 7.9 ns | 45.0 ns |
| 17-digit decimals, 1e-5 to 1e11 | 21.3 ns | 20.8 ns | 73.1 ns |
| 17-digit doubles of every magnitude | 19.0 ns | 21.6 ns | 129.1 ns |

**Strings**, GB/s of input (one 64 KiB string):

| string | hbnf_unescape | a byte loop |
|---|---:|---:|
| a string with no escape | 25.9 GB/s | 2.4 GB/s |
| an escape in 32 bytes | 8.0 GB/s | 2.4 GB/s |
| an escape in 8 bytes | 2.6 GB/s | 2.6 GB/s |

_2026-11-05; gcc -O2, glibc; fast_float v6.1.6; hbnf 4d2f65a.  The integers go through `strtoll` in the last column.  fast_float reads an integer as a `long long`, and a decimal as a `double`._
