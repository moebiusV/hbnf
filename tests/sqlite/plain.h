/* glibc 2.41's headers write gcc's own types (_FloatN, __int128) that neither PCC's grammar nor an ISO C before C23 has:
   made the plain types they stand for, which is all a grammar can ask about the text.  Included with -include. */
#define _Float32 float
#define _Float64 double
#define _Float32x double
#define _Float64x double
#define _Float128 double
#define __int128 long long
