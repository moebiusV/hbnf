#include <stdint.h>
#include <stddef.h>
typedef struct { uint32_t state[4]; uint64_t count; unsigned char buf[64]; } MD5_CTX;
void MD5Init(MD5_CTX *); void MD5Update(MD5_CTX *, const void *, unsigned int); void MD5Final(unsigned char[16], MD5_CTX *);
