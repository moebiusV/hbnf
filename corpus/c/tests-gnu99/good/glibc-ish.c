typedef __builtin_va_list __gnuc_va_list;
extern int printf (const char *__restrict __format, ...) __attribute__ ((__nothrow__));
extern __inline int __attribute__ ((__gnu_inline__)) f (int x) { return x; }
extern int g (void) __attribute__ ((__nothrow__ , __leaf__)) __attribute__ ((__const__));
typedef struct { int __count; __extension__ union { unsigned int __wch; char __wchb[4]; } __value; } __mbstate_t;
int __asm__x;
