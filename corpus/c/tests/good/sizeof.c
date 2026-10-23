int f(int x) { return sizeof x + sizeof(int) + sizeof(int[10]) + sizeof(struct { int a; }); }
