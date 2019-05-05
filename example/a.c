#include "a.h"


inline static int a_inline_static_func(int x);
static int a_static_func2(int x);


//inline static int __func_(int x);
//static int _func__(int x);


struct AA aa_ =
{
    .func = a_inline_static_func
};


//static struct A a_ =
//struct A a_ =
//{
//    .aa = aa_
//};
//

int a_inline_static_func(int x)
{
    if (x > 1000)
    {
        return x;
    }

    return x * x;
}


int  __attribute__((weak)) a_func(int x)
{
    if(x > 1000) 
    {
        return x;
    }

    return a_inline_static_func(x);
}


int a_static_func2(int x)
{
    x = a_func(x+x);
    return a_inline_static_func(x);

}



// mimic function in main calling a_func()
static int main_func(int x)
{
    return a_func(x+x);
}

