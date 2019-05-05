#ifndef A_H
#define A_H

struct AA
{
    int (*func) (int);
};

struct A
{
    struct AA aa;
};


//int a_func(int x);

static struct A a_;
extern struct AA aa_;

#endif 
