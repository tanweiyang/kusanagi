#include <stdio.h>
#include "a.h"

int main_func(int x);

int a_func(int y)
{
    return main_func(y) * y;
}


int main_func_recur(int x)
{
    if(x < 50)
    {
        x = main_func(x);
        return main_func(x);
    }
    else
    {
        return x;
    }
}


int main_func(int x)
{
    return x + main_func_recur(x*2) + a_func(x+x);
}


int main_func2(int x)
{
    return x + main_func_recur(x*2);
}



int main()
{
    struct AA aaa;
    aaa.func = main_func2;

    a_.aa = aa_;

    int x = main_func(7);
    x = aaa.func(x);
    printf("a_.func(%d): %d\n", x, a_.aa.func(x));
    return 0;
}


