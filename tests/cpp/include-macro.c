/* flags: -undef -nostdinc -Itests/cpp */
#define HDR "inc/plain.h"
#include HDR
#define ANGLE <inc/plain.h>
#include ANGLE
#define Q(x) #x
#include Q(inc/plain.h)
int after = __LINE__;
