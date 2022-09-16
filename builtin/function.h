#pragma once

struct $proc;
struct $action;
struct $mut;
struct $pure;
struct $function;
struct $Cont;
struct $Msg;

typedef struct $proc *$proc;
typedef struct $action *$action;
typedef struct $mut *$mut;
typedef struct $pure *$pure;
typedef struct $function *$function;
typedef struct $Cont *$Cont;
typedef struct $Msg *$Msg;


enum $RTAG { $RDONE, $RFAIL, $RCONT, $RWAIT };
typedef enum $RTAG $RTAG;

struct $R {
    $RTAG tag;
    $Cont cont;
    $WORD value;
};
typedef struct $R $R;

#define $R_CONT(cont, arg)      ($R){$RCONT, (cont), ($WORD)(arg)}
#define $R_DONE(value)          ($R){$RDONE, NULL,   (value)}
#define $R_FAIL(value)          ($R){$RFAIL, NULL,   (value)}
#define $R_WAIT(cont, value)    ($R){$RWAIT, (cont), (value)}



struct $proc$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($proc);
    void (*__serialize__)($proc, $Serial$state);
    $proc (*__deserialize__)($proc, $Serial$state);
    $bool (*__bool__)($proc);
    $str (*__str__)($proc);
    $str (*__repr__)($proc);
    $R (*__eval__)($proc, $WORD, $Cont);
    $R (*__exec__)($proc, $WORD, $Cont);
};
struct $proc {
    struct $proc$class *$class;
};
extern struct $proc$class $proc$methods;


struct $action$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($action);
    void (*__serialize__)($action, $Serial$state);
    $action (*__deserialize__)($action, $Serial$state);
    $bool (*__bool__)($action);
    $str (*__str__)($action);
    $str (*__repr__)($action);
    $R (*__eval__)($action, $WORD, $Cont);
    $R (*__exec__)($action, $WORD, $Cont);
    $Msg (*__asyn__)($action, $WORD);
};
struct $action {
    struct $action$class *$class;
};
extern struct $action$class $action$methods;


struct $mut$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($mut);
    void (*__serialize__)($mut, $Serial$state);
    $mut (*__deserialize__)($mut, $Serial$state);
    $bool (*__bool__)($mut);
    $str (*__str__)($mut);
    $str (*__repr__)($mut);
    $R (*__eval__)($mut, $WORD, $Cont);
    $R (*__exec__)($mut, $WORD, $Cont);
    $WORD (*__call__)($mut, $WORD);
};
struct $mut {
    struct $mut$class *$class;
};
extern struct $mut$class $mut$methods;


struct $pure$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($pure);
    void (*__serialize__)($pure, $Serial$state);
    $pure (*__deserialize__)($pure, $Serial$state);
    $bool (*__bool__)($pure);
    $str (*__str__)($pure);
    $str (*__repr__)($pure);
    $R (*__eval__)($pure, $WORD, $Cont);
    $R (*__exec__)($pure, $WORD, $Cont);
    $WORD (*__call__)($pure, $WORD);
};
struct $pure {
    struct $pure$class *$class;
};
extern struct $pure$class $pure$methods;


struct $Cont$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($Cont);
    void (*__serialize__)($Cont, $Serial$state);
    $Cont (*__deserialize__)($Cont, $Serial$state);
    $bool (*__bool__)($Cont);
    $str (*__str__)($Cont);
    $str (*__repr__)($Cont);
    $R (*__call__)($Cont, $WORD);
};
struct $Cont {
    struct $Cont$class *$class;
};
extern struct $Cont$class $Cont$methods;

void $Cont$__init__($Cont);
$bool $Cont$__bool__($Cont);
$str $Cont$__str__($Cont);
void $Cont$__serialize__($Cont, $Serial$state);
$Cont $Cont$__deserialize__($Cont, $Serial$state);

struct $function$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($function);
    void (*__serialize__)($function, $Serial$state);
    $function (*__deserialize__)($function, $Serial$state);
    $bool (*__bool__)($function);
    $str (*__str__)($function);
    $str (*__repr__)($function);
    $WORD (*__call__)($function);
};
struct $function {
    struct $function$class *$class;
};
extern struct $function$class $function$methods;


struct $function1;
typedef struct $function1 *$function1;
struct $function1$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($function1);
    void (*__serialize__)($function1, $Serial$state);
    $function1 (*__deserialize__)($function1, $Serial$state);
    $bool (*__bool__)($function1);
    $str (*__str__)($function1);
    $str (*__repr__)($function1);
    $WORD (*__call__)($function1, $WORD);
};
struct $function1 {
    struct $function1$class *$class;
};

struct $function2;
typedef struct $function2 *$function2;
struct $function2$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($function2);
    void (*__serialize__)($function2, $Serial$state);
    $function2 (*__deserialize__)($function2, $Serial$state);
    $bool (*__bool__)($function2);
    $str (*__str__)($function2);
    $str (*__repr__)($function2);
    $WORD (*__call__)($function2, $WORD, $WORD);
};
struct $function2 {
    struct $function2$class *$class;
};

struct $function3;
typedef struct $function3 *$function3;
struct $function3$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($function3);
    void (*__serialize__)($function3, $Serial$state);
    $function3 (*__deserialize__)($function3, $Serial$state);
    $bool (*__bool__)($function3);
    $str (*__str__)($function3);
    $str (*__repr__)($function3);
    $WORD (*__call__)($function3, $WORD, $WORD, $WORD);
};
struct $function3 {
    struct $function3$class *$class;
};
