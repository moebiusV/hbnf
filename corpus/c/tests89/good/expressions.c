int a, b, c, *p, arr[4];
double dd;
void e(void)
{
    a = b = c = 1;
    a += 2; a -= 2; a *= 2; a /= 2; a %= 2; a <<= 1; a >>= 1; a &= 1; a ^= 1; a |= 1;
    c = a ? b : c ? a : b;
    c = (a, b);
    c = a || b && c | a ^ b & c;
    c = a == b != c < a > b <= c >= a;
    c = a << 1 >> 2 + 3 - 4 * 5 / 6 % 7;
    c = -a + +b - ~c * !a;
    c = *p++ + --*p + p[1] + arr[a++];
    c = (int)dd + (char)a + sizeof(int) + sizeof a;
    p = &arr[2];
    dd = (double)a / 2;
    c = (*p) + (a);
    a = sizeof (int) * 2;
    c = a < b ? (b) : (c);
}
