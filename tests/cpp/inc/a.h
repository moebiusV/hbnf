#ifndef A_H
#define A_H
int from_a = __LINE__;
const char *a_file = __FILE__;
#include "b.h"
int after_b_in_a = __LINE__;
#endif
