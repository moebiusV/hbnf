/* the C of 1979: names for parameters, declared after; implicit int; no prototypes */
int add(a, b)
int a, b;
{
	return a + b;
}
twice(x) { return x * 2; }
char *copy(dst, src)
register char *dst, *src;
{
	char *r;
	r = dst;
	while (*dst++ = *src++)
		;
	return r;
}
main(argc, argv)
char **argv;
{
	return add(argc, 1);
}
