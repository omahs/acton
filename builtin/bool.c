/*
 * Copyright (C) 2019-2021 Data Ductus AB
 *
 * Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 *
 * 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */



// Serialization ///////////////////////////////////////////////////////////////////////

void $bool_init($bool self, $value s){
  self->val = (s->$class->__bool__(s))->val;
}

$bool $bool_bool($bool self) {
  return self;
}

$str $bool_str($bool self) {
  if (self->val)
    return to$str("True");
  else
    return to$str("False");
}

void $bool_serialize($bool self, $Serial$state state) {
  $val_serialize(BOOL_ID,&self->val,state);
}

$bool $bool_deserialize($bool self, $Serial$state state) {
  return to$bool((long)$val_deserialize(state));
}

struct $bool$class $bool$methods = {
    "$bool",
    UNASSIGNED,
    ($Super$class)&$atom$methods,
    $bool_init,
    $bool_serialize,
    $bool_deserialize,
    $bool_bool,
    $bool_str,
    $bool_str
};

$bool $bool$new($value s) {
    return $NEW($bool, s);
}

$bool to$bool(long b) {
  $bool res = malloc(sizeof(struct $bool));
  res->$class = &$bool$methods;
  res->val = b;
  return res;
}
    
long from$bool($bool b) {
  return b->val;
}

struct $bool $t = {&$bool$methods,1L};
struct $bool $f = {&$bool$methods,0L};

$bool $True = &$t;
$bool $False = &$f;


$bool $default__bool__($value self) {
  return $True;
}

// $Eq$bool ///////////////////////////////////////////////////////////////////////////////////

struct $Eq$bool$class $Eq$bool$methods = {
    "$Eq$bool",
    UNASSIGNED,
    ($Super$class)&$Eq$methods,
    $Eq$bool$__init__,
    $Eq$bool$__serialize__,
    $Eq$bool$__deserialize__,
    ($bool (*)($Eq$bool))$default__bool__,
    ($str (*)($Eq$bool))$default__str__,
    ($str (*)($Eq$bool))$default__str__,
    $Eq$bool$__eq__,
    $Eq$bool$__ne__
};

struct $Eq$bool $Eq$bool_instance = {&$Eq$bool$methods};
$Eq$bool $Eq$bool$witness = &$Eq$bool_instance;

void $Eq$bool$__serialize__($Eq$bool self, $Serial$state state) {
}

$Eq$bool $Eq$bool$__deserialize__($Eq$bool self, $Serial$state state) {
   $Eq$bool res = $DNEW($Eq$bool,state);
   return res;
}

$bool $Eq$bool$__eq__ ($Eq$bool self, $bool a, $bool b) {
  return to$bool(a->val == b->val);
}

$bool $Eq$bool$__ne__ ($Eq$bool self, $bool a, $bool b) {
  return to$bool(a->val != b->val);
}

$Eq$bool $Eq$bool$new() {
   return $NEW($Eq$bool);
}

void $Eq$bool$__init__($Eq$bool self) {
   return;
}

// $Hashable$bool ///////////////////////////////////////////////////////////////////////////////////////////////////////

struct $Hashable$bool$class $Hashable$bool$methods = {
    "$Hashable$bool",
    UNASSIGNED,
    ($Super$class)&$Hashable$methods,
    $Hashable$bool$__init__,
    $Hashable$bool$__serialize__,
    $Hashable$bool$__deserialize__,
    ($bool (*)($Hashable$bool))$default__bool__,
    ($str (*)($Hashable$bool))$default__str__,
    ($str (*)($Hashable$bool))$default__str__,
    $Hashable$bool$__eq__,
    $Hashable$bool$__ne__,
    $Hashable$bool$__hash__
};

$Hashable$bool $Hashable$bool$new() {
   return $NEW($Hashable$bool);
}

void $Hashable$bool$__init__($Hashable$bool self) {
   return;
}
void $Hashable$bool$__serialize__($Hashable$bool self, $Serial$state state) {
}

$Hashable$bool $Hashable$bool$__deserialize__($Hashable$bool self, $Serial$state state) {
   $Hashable$bool res = $DNEW($Hashable$bool,state);
   return res;
}

$bool $Hashable$bool$__eq__($Hashable$bool wit, $bool a, $bool b) {
  return to$bool(a->val == b->val);
}

$bool $Hashable$bool$__ne__($Hashable$bool wit, $bool a, $bool b) {
  return to$bool(a->val != b->val);
}

$bool $Hashable$bool$__hash__($Hashable$bool wit, $bool a) {
  return to$bool($int_hash(($int)a));
}
struct $Hashable$bool $Hashable$bool_instance = {&$Hashable$bool$methods};
$Hashable$bool $Hashable$bool$witness = &$Hashable$bool_instance;

