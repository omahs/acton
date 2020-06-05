// classid generation and retrieval ////////////////////////////////////////////////////////

/* 
 * Note that this does not attempt to be thread-safe. 
 * We need to sort out how initialization is to be done.
 */

int PREASSIGNED = 40;

$list $methods;  //key is classid; values are method tables


void $register_force(int classid, $WORD meths) {
  // we require that $methods is big enough to index it at classid. See register_builtin below.
  $list_setitem($methods,classid,meths);
  (($Serializable$methods)meths)->$class_id = classid;
}
    
void $register($WORD meths) {
    $list_append($methods,meths);
    (($Serializable$methods)meths)->$class_id = $methods->length-1;
}


/*
 * We do not register rts classid's here, since we do be able to serialize without including all of rts.o with its  
 * special main and handling of $ROOT. Doing so would complicate testing of builtin types significantly.
 */
void $register_builtin() {
  $methods = $list_new(2*PREASSIGNED); //preallocate space for PREASSIGNED user classes before doubling needed
  memset($methods->data,0,PREASSIGNED*sizeof($WORD)); // initiate PREASSIGNED first slots to NULL;
  $methods->length = PREASSIGNED;
  $register_force(NULL_ID,&$Null$methods);
  $register_force(INT_ID,&$int$methods);
  $register_force(FLOAT_ID,&$float$methods);
  //  $register_force(COMPLEX_ID,&$complex$methods);
  $register_force(BOOL_ID,&$bool$methods);
  $register_force(STR_ID,&$str$methods);
  $register_force(LIST_ID,&$list$methods);
  $register_force(DICT_ID,&$dict$methods);
  $register_force(SET_ID,&$set$methods);
  $register_force(RANGE_ID,&$range$methods);
  $register_force(TUPLE_ID,&$tuple$methods);
  $register_force(STRITERATOR_ID,&$Iterator$str$methods);
  $register_force(LISTITERATOR_ID,&$Iterator$list$methods);
  $register_force(DICTITERATOR_ID,&$Iterator$dict$methods);
  $register_force(VALUESITERATOR_ID,&$Iterator$dict$values$methods);
  $register_force(ITEMSITERATOR_ID,&$Iterator$dict$items$methods);
  $register_force(SETITERATOR_ID,&$Iterator$set$methods);
  $register_force(BASEEXCEPTION_ID,&$BaseException$methods);
  $register_force(SYSTEMEXIT_ID,&$SystemExit$methods);
  $register_force(KEYBOARDINTERRUPT_ID,&$KeyboardInterrupt$methods);
  $register_force(EXCEPTION_ID,&$Exception$methods);
  $register_force(ASSERTIONERROR_ID,&$AssertionError$methods);
  $register_force(LOOKUPERROR_ID,&$LookupError$methods);
  $register_force(INDEXERROR_ID,&$IndexError$methods);
  $register_force(KEYERROR_ID,&$KeyError$methods);
  $register_force(MEMORYERROR_ID,&$MemoryError$methods);
  $register_force(OSERROR_ID,&$OSError$methods);
  $register_force(RUNTIMEERROR_ID,&$RuntimeError$methods);
  $register_force(NOTIMPLEMENTEDERROR_ID,&$NotImplementedError$methods);
  $register_force(VALUEERROR_ID,&$ValueError$methods);
}