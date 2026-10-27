asm("nop");
int x asm("xsym");
void f(int a, int b)
{
    int c;
    asm volatile ("nop");
    __asm__ ("movl %1, %0" : "=r" (c) : "r" (a));
    __asm__ __volatile__ ("add %2, %0" : "=r" (c) : "0" (a), "m" (b) : "memory", "cc");
    asm ("" : : "r" (a));
}
