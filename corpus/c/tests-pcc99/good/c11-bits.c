_Static_assert(1, "ok");
_Alignas(16) char buf[16];
_Atomic int counter;
_Atomic(int) other;
_Noreturn void die(void);
_Thread_local int tl;
int n = _Alignof(int);
int sel(int x) { return _Generic(x, int: 1, long: 2, default: 0); }
struct s { int a; _Static_assert(1, "in a struct"); };
