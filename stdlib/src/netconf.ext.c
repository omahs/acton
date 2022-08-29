
#include "../rts/io.h"
#include "../rts/log.h"

void netconf$$__ext_init__() {
    // NOP
}

$R netconf$$Client$_self (netconf$$Client __self__, $Cont c$cont) {
    return $R_CONT(c$cont, __self__);
}

$NoneType netconf$$Client$call_cb (netconf$$Client __self__, $function cb, $str data) {
    $function2 f = ($function2)cb;
    f->$class->__call__(f, __self__, data);
    return $None;
}
