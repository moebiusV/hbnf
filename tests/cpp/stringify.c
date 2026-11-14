#define STR(x) #x
#define XSTR(x) STR(x)
#define V 42
#define PAIR(a, b) #a "-" #b
const char *a = STR(hello world);
const char *b = STR(  a   +   b  );
const char *c = STR("quoted \"inner\" \\ x");
const char *d = STR('c');
const char *e = XSTR(V);
const char *f = STR(V);
const char *g = STR();
const char *h = PAIR(left, right);
const char *i = STR(f(1, 2));
const char *j = STR(a
   b);
