struct p { int x, y; };
struct p a = { .y = 2, .x = 1 };
int arr[6] = { [4] = 5, [1] = 2, 3 };
struct q { struct p in; int v[3]; } b = { .in.x = 1, .v[2] = 7 };
int trailing[] = { 1, 2, 3, };
