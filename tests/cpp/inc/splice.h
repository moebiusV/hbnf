#ifndef SPLICE_H
#define SPLICE_H
#define TWICE(x) \
   ((x) + \
    (x))
#define LONGNAME_ABC \
  42
int in_header = __LINE__;
int multi = TWICE(LONGNAME_ABC);
int after_splice_header = __LINE__;
#endif
