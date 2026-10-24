**100,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 71 ms | 1405 K sensors/s | 86 MB/s | 7.3 MB |
| hbnf binding (`--conf`) | 6.14 MB | 58 ms | 1730 K sensors/s | 106 MB/s | 7.3 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 717 ms | 1394 K sensors/s | 87 MB/s | 69.0 MB |
| hbnf binding (`--conf`) | 62.39 MB | 581 ms | 1722 K sensors/s | 107 MB/s | 68.8 MB |

_Measured 2026-10-24 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 4.34 on the host, hbnf aaf9aa9; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
