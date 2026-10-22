**100,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 111 ms | 905 K sensors/s | 56 MB/s | 7.2 MB |
| hbnf binding (`--conf`) | 6.14 MB | 115 ms | 867 K sensors/s | 53 MB/s | 7.3 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 1.07 s | 931 K sensors/s | 58 MB/s | 68.8 MB |
| hbnf binding (`--conf`) | 62.39 MB | 1.16 s | 862 K sensors/s | 54 MB/s | 69.0 MB |

_Measured 2026-10-22 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 6.87 on the host, hbnf eb40679; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
