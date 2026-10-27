typedef int myint;
typedef myint *intp, arr10[10];
typedef struct instr instr;
struct instr { int op; };
myint f(myint x) { return x; }
void g(void)
{
    myint myint2;
    intp p;
    arr10 a;
    {
        int myint;
        myint = 1;
    }
    {
        typedef char myint2x;
        myint2x c;
        c = 0;
    }
    (void)p; (void)a;
}
void h(myint, int *);
instr *mk(void);
unsigned myint2;
