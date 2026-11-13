#define A 1
#define B 0
#define N 10
#define M (N * 2 + 1)
#define U 3u
#if A
int a1;
#endif
#if A && !B
int a2;
#endif
#if N > 5 && N < 20
int a3;
#endif
#if M == 21
int a4;
#endif
#if (N + 2) * 3 == 36 ? 1 : 0
int a5;
#endif
#if B || defined(A) && !defined(Z)
int a6;
#endif
#if defined N && defined(M)
int a7;
#endif
#if Z
int never1;
#endif
#if Z == 0
int a8;
#endif
#if 0x10 == 16 && 010 == 8 && 'a' == 97 && '\n' == 10
int a9;
#endif
#if -1 < 0 && -1 > 0u
int a10;
#endif
#if (2 || 1 / 0) && !(0 && 1 / 0) && (1 ? 2 : 1 / 0) == 2
int a11;
#endif
#if 1 << 3 == 8 && 256 >> 4 == 16 && (-8 >> 1) == -4
int a12;
#endif
#if 0
int never2;
#elif N > 100
int never3;
#elif N > 5
int a13;
#elif 1
int never4;
#else
int never5;
#endif
#ifdef Z
int never6;
#elif defined A
int a14;
#else
int never7;
#endif
#ifndef Z
int a15;
#elif 1
int never8;
#endif
#if 0
#if garbage ( here
#else
int never9;
#endif
#define IN_DEAD 1
#else
int a16;
#endif
#ifdef IN_DEAD
int never10;
#endif
#if /* comment */ A // trailing
int a17;
#endif
#if \
    A
int a18;
#endif
#if(A)
int a19;
#endif
