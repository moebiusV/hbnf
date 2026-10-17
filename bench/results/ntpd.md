**100,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 6.14 MB | 72 ms | 1382 K sensors/s | 85 MB/s | 7.3 MB |
| hbnf binding (`--conf`) | 6.14 MB | 60 ms | 1663 K sensors/s | 102 MB/s | 7.4 MB |

**1,000,000 sensors** (one `sensor` line each, the same file for both):

| tool | input | parse time | sensors/s | MB/s | peak RSS |
|---|---:|---:|---:|---:|---:|
| OpenBSD ntpd parse.y, byacc | 62.39 MB | 724 ms | 1381 K sensors/s | 86 MB/s | 69.0 MB |
| hbnf binding (`--conf`) | 62.39 MB | 622 ms | 1607 K sensors/s | 100 MB/s | 68.8 MB |

_Measured 2026-10-17 on AMD Ryzen 5 7600 6-Core Processor (12 threads), load 8.69 on the host, hbnf e8830cd; gcc 15.2.0, byacc 20260126, bison 3.8.2, flex 2.6.4, peg/leg 0.1.18, tree-sitter 0.27.1, ANTLR 4.13.2 on 21.0.12 2026-07-21; best of 5 runs, one process per run, `gcc -O2`._
