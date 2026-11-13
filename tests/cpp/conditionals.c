#define ON
#ifdef ON
int on;
#else
int off;
#endif
#ifndef ON
int not_on;
#else
int still_on;
#endif
#ifdef OFF
int a;
#endif
#if 0
int dead;
#else
int alive;
#endif
#if 1
int one;
#endif
#if defined(ON)
int d1;
#endif
#if !defined(OFF)
int d2;
#endif
#ifdef ON
  #ifdef OFF
  int inner_off;
  #else
  int inner_on;
  #endif
#endif
#ifdef OFF
  #ifdef ON
  int nested_dead;
  #else
  int nested_dead2;
  #endif
#else
int outer_else;
#endif
#define X 1
#ifdef X
int x = X;
#endif
