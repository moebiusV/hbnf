**100,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 85 ms | 1177 K sensors/s | 72 MB/s | 7.3 MB |
| hbnf binding (`--conf`) | 6.14 MB | 67 ms | 1498 K sensors/s | 92 MB/s | 7.3 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 745 ms | 1343 K sensors/s | 84 MB/s | 68.9 MB |
| hbnf binding (`--conf`) | 62.39 MB | 673 ms | 1487 K sensors/s | 93 MB/s | 68.8 MB |

_Measured 2026-10-23 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.08 on the host, hbnf cd94a16; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
