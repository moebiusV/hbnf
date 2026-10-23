struct s { int a; struct s *n; };
int f(struct s *p, struct s v) { return p->a + p->n->a + v.a; }
