#include "b.h"
#include "a.h"

int *b_;

int b_func (int x);

static int b_static_func(int x)
{
    b_[1] = 5;
    return b_func(x);
}


int b_func (int x)
{
    return x * b_[1];
}


