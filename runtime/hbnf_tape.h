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
/* tape_hard is the room tape_reserve took; tape_cap is how much of it is backed with pages so far (a window of
   32768 words, 256 KiB, ahead of the writes, backed in one call each: not one page fault for each page).  The
   fast path checks tape_cap alone; where the room is not reserved, tape_hard is 0 and tape_cap is all of it. */
static size_t tape_hard;
#if defined(MADV_POPULATE_WRITE)
enum { TAPE_WINDOW = 1 << 15 };
static void tape_populate (size_t from, size_t to)
{
    uintptr_t a = ((uintptr_t) (tape + from)) & ~(uintptr_t) 4095, b = ((uintptr_t) (tape + to) + 4095) & ~(uintptr_t) 4095;
    madvise ((void *) a, b - a, MADV_POPULATE_WRITE);
}
#endif

/* A tape that outgrows its room doubles; this is the way out of the fast path, not the usual one. */
static __attribute__((noinline, unused)) void tape_grow (void)
{
    size_t cap;
    uint64_t *t;
#if defined(MADV_POPULATE_WRITE)
    if (tape_cap < tape_hard) {
        cap = tape_cap + TAPE_WINDOW;
        if (cap > tape_hard) cap = tape_hard;
        tape_populate (tape_cap, cap);
        tape_cap = cap;
        return;
    }
#endif
    cap = tape_cap ? tape_cap * 2 : 1 << 16;
    t = realloc (tape, cap * sizeof *tape);
    if (!t) abort ();
    tape = t;
    tape_cap = tape_hard = cap;
}

/* Room for a document of this many bytes, before the parse: a quarter word a byte is more
   than the usual document needs.  The room starts on a 2 MiB boundary, so the kernel can back it with huge
   pages where it has them; it does not ask for them unless -DHBNF_HUGEPAGES (see the arena of a generated
   parser: on a fragmented host the request makes every fault try to compact memory and a parse takes
   three to eight times as long). */
__attribute__((unused)) static void tape_reserve (size_t input_bytes)
{
    const size_t huge = (size_t) 2 << 20;
    size_t bytes = ((input_bytes / 4 + 64) * sizeof *tape + huge - 1) & ~(huge - 1);
    void *m = aligned_alloc (huge, bytes);
    if (!m) return;
#if defined(MADV_HUGEPAGE) && defined(HBNF_HUGEPAGES)
    madvise (m, bytes, MADV_HUGEPAGE);
#endif
    free (tape);
    tape = m;
    tape_cap = tape_hard = bytes / sizeof *tape;
#if defined(MADV_POPULATE_WRITE)
    tape_cap = TAPE_WINDOW < tape_hard ? TAPE_WINDOW : tape_hard;
    tape_populate (0, tape_cap);
#endif
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
