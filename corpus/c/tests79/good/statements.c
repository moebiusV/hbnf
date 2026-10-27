f(n)
{
	int i, t;
	char buf[10], *p;
	t = 0;
	for (i = 0; i < n; i++) {
		if (i % 2) continue;
		else if (i > 7) break;
		t += i;
	}
	for (;;) break;
	while (n-- > 0) t--;
	do t++; while (t < 0);
	switch (n) {
	case 0:
	case 1: t = 1; break;
	default: t = 2;
	}
	goto done;
done:
	asm("nop");
	return t ? t : -1;
}
