struct p { int x; };
void f(void) { struct p *q = &(struct p){ 1 }; }
