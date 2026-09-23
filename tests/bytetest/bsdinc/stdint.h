/* shim stdint.h — POSIX fixed-width names over OpenBSD's machine/_types.h,
 * so OpenBSD daemon headers compile under -nostdinc against OpenBSD's own
 * headers.  OpenBSD gets <stdint.h> from the compiler; this reproduces the
 * mapping (see the §7.18.1 block in the arch's _types.h). */
#ifndef _HBNF_SHIM_STDINT_H_
#define _HBNF_SHIM_STDINT_H_

#include <machine/_types.h>

typedef __int8_t   int8_t;
typedef __uint8_t  uint8_t;
typedef __int16_t  int16_t;
typedef __uint16_t uint16_t;
typedef __int32_t  int32_t;
typedef __uint32_t uint32_t;
typedef __int64_t  int64_t;
typedef __uint64_t uint64_t;

typedef __int_least8_t   int_least8_t;
typedef __uint_least8_t  uint_least8_t;
typedef __int_least16_t  int_least16_t;
typedef __uint_least16_t uint_least16_t;
typedef __int_least32_t  int_least32_t;
typedef __uint_least32_t uint_least32_t;
typedef __int_least64_t  int_least64_t;
typedef __uint_least64_t uint_least64_t;

typedef __int_fast8_t   int_fast8_t;
typedef __uint_fast8_t  uint_fast8_t;
typedef __int_fast16_t  int_fast16_t;
typedef __uint_fast16_t uint_fast16_t;
typedef __int_fast32_t  int_fast32_t;
typedef __uint_fast32_t uint_fast32_t;
typedef __int_fast64_t  int_fast64_t;
typedef __uint_fast64_t uint_fast64_t;

typedef __intptr_t   intptr_t;
typedef __uintptr_t  uintptr_t;
typedef __intmax_t   intmax_t;
typedef __uintmax_t  uintmax_t;

/* Limits (§7.18.2/7.18.3) — the compiler's <stdint.h> normally provides
 * these; reproduce the C99 values (amd64's least/fast types are the fixed
 * ones, so their macros alias). */
#define INT8_MIN    (-127 - 1)
#define INT16_MIN   (-32767 - 1)
#define INT32_MIN   (-2147483647 - 1)
#define INT64_MIN   (-9223372036854775807LL - 1)
#define INT8_MAX    127
#define INT16_MAX   32767
#define INT32_MAX   2147483647
#define INT64_MAX   9223372036854775807LL
#define UINT8_MAX   255
#define UINT16_MAX  65535
#define UINT32_MAX  4294967295U
#define UINT64_MAX  18446744073709551615ULL

#define INT_LEAST8_MIN   INT8_MIN
#define INT_LEAST16_MIN  INT16_MIN
#define INT_LEAST32_MIN  INT32_MIN
#define INT_LEAST64_MIN  INT64_MIN
#define INT_LEAST8_MAX   INT8_MAX
#define INT_LEAST16_MAX  INT16_MAX
#define INT_LEAST32_MAX  INT32_MAX
#define INT_LEAST64_MAX  INT64_MAX
#define UINT_LEAST8_MAX  UINT8_MAX
#define UINT_LEAST16_MAX UINT16_MAX
#define UINT_LEAST32_MAX UINT32_MAX
#define UINT_LEAST64_MAX UINT64_MAX

#define INT_FAST8_MIN    INT8_MIN
#define INT_FAST16_MIN   INT16_MIN
#define INT_FAST32_MIN   INT32_MIN
#define INT_FAST64_MIN   INT64_MIN
#define INT_FAST8_MAX    INT8_MAX
#define INT_FAST16_MAX   INT16_MAX
#define INT_FAST32_MAX   INT32_MAX
#define INT_FAST64_MAX   INT64_MAX
#define UINT_FAST8_MAX   UINT8_MAX
#define UINT_FAST16_MAX  UINT16_MAX
#define UINT_FAST32_MAX  UINT32_MAX
#define UINT_FAST64_MAX  UINT64_MAX

#define INTPTR_MIN  INT64_MIN
#define INTPTR_MAX  INT64_MAX
#define UINTPTR_MAX UINT64_MAX
#define INTMAX_MIN  INT64_MIN
#define INTMAX_MAX  INT64_MAX
#define UINTMAX_MAX UINT64_MAX
#define PTRDIFF_MIN INT64_MIN
#define PTRDIFF_MAX INT64_MAX
#define SIZE_MAX    UINT64_MAX

#endif
