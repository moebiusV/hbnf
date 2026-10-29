/* stdarg without the compiler's builtins, so that a strict grammar reads what SQLite wrote and not
   what gcc's <stdarg.h> turns it into. */
#define _STDARG_H
#define __DEFINED_va_list
#define __DEFINED___isoc_va_list
typedef void *va_list;
typedef void *__isoc_va_list;
#define va_start(a, b) ((void)0)
#define va_end(a) ((void)0)
#define va_arg(a, T) (*(T *)0)
#define va_copy(d, s) ((void)0)
