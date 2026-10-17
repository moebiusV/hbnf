# bech32 corpus

bech32 (BIP-173) and bech32m (BIP-350), the address encoding of segwit: a
human-readable part, a `1`, then 5-bit symbols from a 32-character set, the last
six of them a BCH checksum.  Test data for the wire layer (`tests/wire/segwit.hbnf`
reads the data part).

    corpus/bech32/
      README.md        this file
      SHA256SUMS       the hash of each file, as taken
      segwit_addr.c    the reference implementation, unchanged
      segwit_addr.h    its header, unchanged

## Source and attribution

- **Reference implementation:** Pieter Wuille's `ref/c/segwit_addr.c` and
  `segwit_addr.h`, <https://github.com/sipa/bech32> (commit
  `7a7d7ab158db7078a333384e0e918c90dbc42917`, 2022-05-31), Copyright (c) 2017,
  2021 Pieter Wuille, MIT licence (the notice is at the head of each file).
- **Standards:** BIP-173 (Wuille, Maxwell) and BIP-350 (Wuille).
- The addresses in `tests/wire/segwit_main.c` are the published valid examples.

## Status

Saved so the reference is in the repository.  Nothing here is called yet.  The
checksum covers the human-readable part (`bc`, `tb`) as well as the data, and the
segwit grammar reads only the data symbols, so it reads the checksum and does not
check it.  When the grammar can bring the human-readable part in, an `%action`
calls `bech32_decode` from here, by its own name, and links `segwit_addr.c`.
