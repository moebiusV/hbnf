/* hbnf_rb.h -- what `layout rb` (layouts/rb/layout.hbnf) needs besides OpenBSD's <sys/tree.h>, which is
 * here too (sys/tree.h, v1.31, unchanged, with a one-line sys/_null.h) for hosts that have none.  */
#ifndef HBNF_RB_H
#define HBNF_RB_H
#include <stddef.h>
#include <string.h>
#ifndef __unused                 /* the BSDs' spelling, which tree.h uses; sys/_null.h is beside it here */
#define __unused __attribute__((__unused__))
#endif
#include <sys/tree.h>

/* The key of a string field of the tree (an hbnf_str): a pointer and a length, as the comparison takes. */
#define HBNF_RB_STR(s) hbnf_sp (s), hbnf_sn (s)

/* Keys compare as bytes, a shorter key first when it is a prefix of the other. */
static inline int hbnf_keycmp(const char *a, size_t an, const char *b, size_t bn) {
    int c = memcmp(a, b, an < bn ? an : bn);
    return c ? c : (an > bn) - (an < bn);
}
#endif
