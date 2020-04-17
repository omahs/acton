
/*
-------------------------------- original

actor Pingpong(i):
    var count = 0
    async def ping(q):
        count += 1
        print('Ping %d', count*q)
        postpone(1, pong, count, -q)
    def pong(n,q):
        print('     %d Pong', n*q)
        postpone(2, ping, -q)
    ping(i)

-------------------------------- explicit ASYNC

actor Pingpong(i):
    var count = 0
    def ping(q):
        count += 1
        print('Ping %d', count*q)
        _ = pong(count, q)
        return None
    def pong(n,q):
        print('     %d Pong', n*q)
        ASYNC_(self, lambda: ping(q))
        return None
    ASYNC_(self, lambda: ping(i))

-------------------------------- explicit ACTOR

def Pingpong(i):
    self = ACTOR(1)
    self.count = 0
    def ping(q):
        self.count += 1
        print('Ping %d', self.count*q)
        _ = pong(self.count, q)
        return None
    def pong(n,q):
        print('     %d Pong', n*q)
        ASYNC_(self, lambda: ping(q))
        return None
    ASYNC_(self, lambda: ping(i))
    return self

-------------------------------- CPS

def Pingpong(i, then):
    self = ACTOR(1)
    self.count = 0
    def ping(q, then):
        self.count +=1
        print('Ping %d', self.count*q)
        return _CONT(lambda _: pong(self.count, q, then), None)
    def pong(n, q, then):
        print('     %d Pong', n*q)
        ASYNC(self, lambda th: ping(q,th))
        return _CONT(then, None)
    ASYNC(self, lambda th: ping(i,th))
    return _CONT(then, self)

-------------------------------- explicit lambdas

def Pingpong(i, then):
    self = ACTOR(1)
    self.count = 0
    def ping(q, then):
        self.count +=1
        print('Ping %d', self.count*q)
        def lam1(_):
            return pong(self.count, q, then)
        return _CONT(lam1, None)
    def pong(n, q, then):
        print('     %d Pong', n*q)
        def ping1(th):
            return ping(q, th)
        ASYNC(self, ping1)
        return _CONT(then, None)
    def ping2(th):
        return ping(i, th)
    ASYNC(self, ping2)
    return _CONT(then, self)

-------------------------------- closure-conversion

def Pingpong(i, then):
    self = ACTOR(1)
    self.count = 0
    def ping(self, q, then):
        self.count +=1
        print('Ping %d', self.count*q)
        def lam1(self, q, then, _):
            return pong(self, self.count, q, then)
        return _CONT(CLOS3(lam1,self,q,then), None)
    def pong(self, n, q, then):
        print('     %d Pong', n*q)
        def ping1(self, q, th):
            return ping(self, q, th)
        ASYNC(self, CLOS2(ping1,self,q))
        return _CONT(then, None)
    def ping2(self, i, th):
        return ping(self, i, th)
    ASYNC(self, CLOS2(ping2,self,i))
    return _CONT(then, self)

-------------------------------- lambda-lifting

def lam1(self, q, then, _):
    return pong(self, self.count, q, then)

def ping(self, q, then):
    self.count +=1
    print('Ping %d', self.count*q)
    return _CONT(CLOS3(lam1,self,q,then), None)

def ping1(self, q, th):
    return ping(self, q, th)

def pong(self, n, q, then):
    print('     %d Pong', n*q)
    ASYNC(self, CLOS2(ping1,self,q))
    return _CONT(then, None)

def ping2(self, i, th):
    return ping(self, i, th)

def Pingpong(i, then):
    self = ACTOR(1)
    self.count = 0
    ASYNC(self, CLOS2(ping2,self,i))
    return _CONT(then, self)

-------------------------------- explicit this

def lam1(this, _):
    return pong(this.self, this.self.count, this.q, this.then)

def ping(self, q, then):
    self.count +=1
    print('Ping %d', self.count*q)
    return _CONT(CLOS3(lam1,self,q,then), None)

def ping1(this, th):
    return ping(this.self, this.q, th)

def pong(self, n, q, then):
    print('     %d Pong', n*q)
    ASYNC(self, CLOS2(ping1,self,q))
    return _CONT(then, None)

def ping2(this, th):
    return ping(this.self, this.i, th)

def Pingpong(this, then):
    self = ACTOR(1)
    self.count = 0
    ASYNC(self, CLOS2(ping2,self,this.i))
    return _CONT(then, self)

-------------------------------- anonymous variable arrays

def lam1(this, _):
    return pong(this[0], this[0][0], this[1], this[2])

def ping(self, q, then):
    self[0] +=1
    print('Ping %d', self[0]*q)
    return _CONT(CLOS3(lam1,self,q,then), None)

def ping1(this, th):
    return ping(this[0], this[1], th)

def pong(self, n, q, then):
    print('     %d Pong', n*q)
    ASYNC(self, CLOS2(ping1,self,q))
    return _CONT(then, None)

def ping2(this, th):
    return ping(this[0], this[1], th)

def Pingpong(this, then):
    self = ACTOR(1)
    self[0] = 0
    ASYNC(self, CLOS2(ping2,self,this[0]))
    return _CONT(then, self)

-------------------------------- explicit var and state offsets

def lam1(this, _):
    return pong(this.var[0], this.var[0].state[0], this.var[1], this.var[2])

def ping(self, q, then):
    self.state[0] +=1
    print('Ping %d', self.state[0]*q)
    return _CONT(CLOS3(lam1,self,q,then), None)

def ping1(this, th):
    return ping(this.var[0], this.var[1], th)

def pong(self, n, q, then):
    print('     %d Pong', n*q)
    ASYNC(self, CLOS2(ping1,self,q))
    return _CONT(then, None)

def ping2(this, th):
    return ping(this.var[0], this.var[1], th)

def Pingpong(this, then):
    self = ACTOR(1)
    self.state[0] = 0
    ASYNC(self, CLOS2(ping2,self,this.var[0]))
    return _CONT(then, self)

*/

////// builtins...

typedef char *$str;
typedef int $int;

#define $int_add(a,b)       ((int)a + (int)b)
#define $int_mul(a,b)       ((int)a * (int)b)
#define $int_neg(a)         (-(int)a)

#include "rts.h"

struct Pingpong;
struct Pingpong$class;
typedef struct Pingpong *Pingpong;
void Pingpong$__init__(Pingpong, $int);
$R Pingpong$ping(Pingpong, $int, $Cont);
$R Pingpong$pong(Pingpong, $int, $int, $Cont);

struct Pingpong {
    union {
        struct Pingpong$class *__class__;
        struct $ACTOR super;
    };
    int count;
};
struct Pingpong$class {
    char *GCINFO;
    void (*__init__)(Pingpong,$int);
    $R (*ping)(Pingpong,int,$Cont);
    $R (*pong)(Pingpong,int,int,$Cont);
} Pingpong$methods = {
    "Pingpong",
    Pingpong$__init__,
    Pingpong$ping,
    Pingpong$pong
};

void Pingpong$__init__(Pingpong self, $int i) {
    $ACTOR$methods.__init__(($ACTOR)self);
    self->count = i;
}

$R Pingpong$ping(Pingpong self, $int q, $Cont then) {
    self->count = $int_add(self->count, 1);
    $int j = $int_mul(self->count, q);
    printf("Ping %8d\n", j);
    $AFTER(1, $CONTINUATION(self->__class__->pong, 3, self, self->count, $int_neg(q)));
    return $CONTINUE(then, j);
}

$R Pingpong$pong(Pingpong self, $int n, $int q, $Cont then) {
    $int j = $int_mul(n, q);
    printf("     %8d Pong\n", j);
    $AFTER(2, $CONTINUATION(self->__class__->ping, 2, self, $int_neg(q)));
    return $CONTINUE(then, $None);
}

$R NEWPingpong(int i, $Cont then) {
    Pingpong self = $NEW(Pingpong, 10);
    $ASYNC(($ACTOR)self, $CONTINUATION(self->__class__->ping, 2, self, i));
    return $CONTINUE(then, self);
}
