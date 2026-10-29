/* hbnf_tape.h: a tape of 64-bit words for a grammar that reads a document with %emit and builds no
   tree (corpus/json/json-tape.hbnf, corpus/toml/toml-tape.hbnf).  Include it in the grammar's
   prologue, after an enum of the grammar's own tags (1 to 255) and two macros that say which of
   them hold a link (TAPE_IS_OPENER) and which a text (TAPE_IS_TEXT); the test drivers use them.

   One word for each value or key: the tag in the top byte.  A text (a string, a number, a key)
   holds its length (16 bits) and where it starts in the input (40 bits); a text of 65535 bytes or
   more says 65535 there and has its length in the word after.  A part that holds others (an
   object, an array, a table) holds the tape position after it, so a reader can skip it; a tag
   alone (a literal) holds nothing. */
#ifndef HBNF_TAPE_H
#define HBNF_TAPE_H
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>

#define TAPE_TAG(t) ((uint64_t) (t) << 56)
#define TAPE_LONG 0xFFFFu
static uint64_t *tape;
static size_t tape_n, tape_cap;

/* A tape that outgrows its room doubles; this is the way out of the fast path, not the usual one. */
static __attribute__((noinline, unused)) void tape_grow (void)
{
    size_t cap = tape_cap ? tape_cap * 2 : 1 << 16;
    uint64_t *t = realloc (tape, cap * sizeof *tape);
    if (!t) abort ();
    tape = t;
    tape_cap = cap;
}

/* Room for a document of this many bytes, before the parse: an eighth of a word a byte is more
   than the usual document needs.  The room starts on a 2 MiB boundary and asks for huge pages, so
   filling it costs a few page faults, not one for every 4 KiB. */
__attribute__((unused)) static void tape_reserve (size_t input_bytes)
{
    const size_t huge = (size_t) 2 << 20;
    size_t bytes = ((input_bytes / 8 + 64) * sizeof *tape + huge - 1) & ~(huge - 1);
    void *m = aligned_alloc (huge, bytes);
    if (!m) return;
#ifdef MADV_HUGEPAGE
    madvise (m, bytes, MADV_HUGEPAGE);
#endif
    free (tape);
    tape = m;
    tape_cap = bytes / sizeof *tape;
}

static inline void tape_put (uint64_t w)
{
    if (__builtin_expect (tape_n + 1 > tape_cap, 0)) tape_grow ();
    tape[tape_n++] = w;
}

/* A text of n bytes that ends at `end` in the input: the parser's position, just after the token. */
static inline void tape_text_of (uint64_t tag, size_t end, size_t n)
{
    uint64_t start = end - n;
    if (__builtin_expect (n >= TAPE_LONG, 0)) {
        tape_put (TAPE_TAG (tag) | (uint64_t) TAPE_LONG << 40 | start);
        tape_put (n);
    } else {
        tape_put (TAPE_TAG (tag) | (uint64_t) n << 40 | start);
    }
}
static inline uint64_t tape_open (uint64_t tag)
{
    uint64_t at = tape_n;
    tape_put (TAPE_TAG (tag));
    return at;
}
static inline void tape_close (uint64_t at)
{
    tape[at] |= tape_n;
}
#endif
