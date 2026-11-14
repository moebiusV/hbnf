#include "inc/a.h"
#define X "inc/b.h"
#include X
#define NAME "inc/a.h"
#include NAME
#ifdef A_H
int guarded_ok;
#endif
#if 1
#include "inc/b.h"
#endif
int use_b = B_MACRO(2);
int line_in_main = __LINE__;
const char *main_file = __FILE__;

#include "inc/once.h"
#include "inc/once.h"
int after_once;
