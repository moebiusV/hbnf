typedef struct s { int a; } instr;
int f(instr *instr) { return instr->a; }
int g(instr *p) { instr q; return p->a; }
