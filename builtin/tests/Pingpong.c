#include "Pingpong.h"

void lambda$1$__init__(lambda$1 $this, Pingpong self, $int count) {
    $this->self = self;
    $this->count = count;
    printf("BBB\n");
}
void lambda$1$__serialize__(lambda$1 $this, $Serial$state state) {
    $step_serialize($this->self,state);
    $step_serialize($this->count,state);
}

lambda$1 lambda$1$__deserialize__($Serial$state state) {
    lambda$1 res = $DNEW(lambda$1,state);
    res->self = (Pingpong)$step_deserialize(state);
    res->count = ($int)$step_deserialize(state);
    return res;
}
$R lambda$1$__call__(lambda$1 $this, $Cont then) {
    Pingpong self = $this->self;
    $int count = $this->count;
    return self->$class->pong(self, $Integral$int$witness->$class->__neg__($Integral$int$witness, count), then);
}

void lambda$2$__init__(lambda$2 $this, Pingpong self) {
    $this->self = self;
}
void lambda$2$__serialize__(lambda$2 $this, $Serial$state state) {
    $step_serialize($this->self,state);
}
lambda$2 lambda$2$__deserialize__($Serial$state state) {
    lambda$2 res = $DNEW(lambda$2,state);
    res->self = (Pingpong)$step_deserialize(state);
    return res;
}
$R lambda$2$__call__(lambda$2 $this, $Cont then) {
    Pingpong self = $this->self;
    return self->$class->ping(self, then);
}

$R Pingpong$__init__(Pingpong self, $Env env, $Cont then) {
    $Actor$methods.__init__(($Actor)self);
    self->i = to$int(7);
    self->count = to$int(0);
    return self->$class->ping(self, then);
}
$R Pingpong$ping(Pingpong self, $Cont then) {
    self->count = $Integral$int$witness->$class->__add__($Integral$int$witness, self->count, to$int(1));
    printf("%ld Ping %ld\n", self->i->val, self->count->val);
    $AFTER(to$int(1), ($Cont)$NEW(lambda$1, self, self->count));
    printf("AAA\n");
    return $R_CONT(then, $None);
}
void Pingpong$__serialize__(Pingpong self, $Serial$state state) {
    $step_serialize(self->i,state);
    $step_serialize(self->count,state);
}
Pingpong Pingpong$__deserialize__($Serial$state state) {
    Pingpong res = $DNEW(Pingpong,state);
    res->i = ($int)$step_deserialize(state);
    res->count = ($int)$step_deserialize(state);
    return res;
}
$R Pingpong$pong(Pingpong self, $int q, $Cont then) {
    printf("%ld     %ld Pong\n", self->i->val, q->val);
    $AFTER(to$int(2), ($Cont)$NEW(lambda$2, self));
    return $R_CONT(then, $None);
}

struct lambda$1$class lambda$1$methods = {
    "lambda$1",
    NULL,
    lambda$1$__init__,
    lambda$1$__serialize__,
    lambda$1$__deserialize__,
    lambda$1$__call__
};
struct lambda$2$class lambda$2$methods = {
    "lambda$2",
    NULL,
    lambda$2$__init__,
    lambda$2$__serialize__,
    lambda$2$__deserialize__,
    lambda$2$__call__
};
struct Pingpong$class Pingpong$methods = {
    "Pingpong",
    NULL,
    Pingpong$__init__,
    Pingpong$__serialize__,
    Pingpong$__deserialize__,
    Pingpong$ping,
    Pingpong$pong
};

$R Pingpong$new($Env env, $Cont cont) {
    Pingpong $tmp = malloc(sizeof(struct Pingpong));
    $tmp->$class = &Pingpong$methods;
    return Pingpong$methods.__init__($tmp, env, $CONSTCONT($tmp, cont));
}

$R $ROOT ($Env env, $Cont cont) {
    $register(&lambda$1$methods);
    $register(&lambda$2$methods);
    $register(&Pingpong$methods);
    return Pingpong$new(env, cont);
}
