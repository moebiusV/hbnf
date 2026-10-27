int a, b, c, *p, arr[4];
double d;
f()
{
	c = a ? b : c ? a : b;
	c = (a, b);
	c = a || b && c | a ^ b & c;
	c = a == b != c < a > b <= c >= a;
	c = a << 1 >> 2 + 3 - 4 * 5 / 6 % 7;
	c = -a - ~c * !b;
	c = *p++ + --*p + p[1] + arr[a++];
	c = (int)d + (char)a + sizeof(int) + sizeof a;
	p = &arr[2];
	d = (double)a / 2;
	c = 0x1f + 017 + 08 + 10L + 0xFFl;
	d = 1.5 + .5 + 2. + 1e3 + 1.5E-2;
	c = 'a' + '\n' + '\0' + 'ab';
	p = "text\n";
}
