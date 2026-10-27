struct point { int x, y; };
struct node { int v; struct node *next; };
union u { int i; char c[4]; };
enum color { RED, GREEN = 5, BLUE };
struct flags { unsigned a : 1; unsigned : 3; unsigned b : 4; };
struct point origin = { 0, 0 };
struct point pts[] = { { 1, 2 }, { 3, 4 }, };
enum color pick(void) { return GREEN; }
int dist(struct point *p) { return p->x * p->x + (*p).y * (*p).y; }
struct tree { struct tree *l, *r; enum color c; } root;
typedef struct point point_t;
typedef point_t *point_p;
point_p mk(void) { return 0; }
