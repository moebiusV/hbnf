struct p { int x, y; };
struct p f(void) { return (struct p){1, 2}; }
int *g(void) { return (int[]){1, 2, 3}; }
