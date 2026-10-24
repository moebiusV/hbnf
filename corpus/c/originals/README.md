# The yacc grammars of C that `bench/notation.sh` counts

Reproduced unchanged, as data for the comparison in the README's notation table; each keeps its
own copyright notice and licence.

| file | what | source |
|---|---|---|
| `pcc-cgram.y` | the Portable C Compiler's grammar, NetBSD trunk (commit `9db636f` of the local checkout) | `cc/ccom/cgram.y` of PCC |
| `v32-cgram.y` | UNIX/32V's C grammar | `usr/src/cmd/mip/cgram.y` of the `Bell-32V` tag of <https://github.com/dspinellis/unix-history-repo> |
| `gcc-4.0.4-c-parse.in` | GCC's last bison grammar for C, before 4.1 replaced it with a hand-written parser; the Objective-C sections (`@@ifobjc`) are left out of the count | `gcc/c-parse.in` of the `releases/gcc-4.0.4` tag of <https://github.com/gcc-mirror/gcc> |
