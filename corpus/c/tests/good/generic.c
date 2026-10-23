int f(int x) { return _Generic(x, int: 1, char: 2, default: 3); }
