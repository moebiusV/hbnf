#define F(a, b) a
#define G(a) a
#define V(a, ...) a
#define Z() 1
int x = F(1);
int y = F(1,2,3);
int z = G(1,2);
int w = V();
int v = V(1);
int u = Z(1);
int t = Z();
