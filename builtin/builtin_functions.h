// print /////////////////////////////////////////////////////////////////

void $print(int size, ...);

// enumerate ////////////////////////////////////////////////////////////

struct $Iterator$enumerate;
typedef struct $Iterator$enumerate *$Iterator$enumerate;

struct $Iterator$enumerate$class {
  char *$GCINFO;
  int $class_id;
  $Super$class $superclass;
  void (*__init__)($Iterator$enumerate, $Iterator,$int);
  void (*__serialize__)($Iterator$enumerate,$Serial$state);
  $Iterator$enumerate (*__deserialize__)($Iterator$enumerate,$Serial$state);
  $bool (*__bool__)($Iterator$enumerate);
  $str (*__str__)($Iterator$enumerate);
  $WORD(*__next__)($Iterator$enumerate);
};

struct $Iterator$enumerate {
  struct $Iterator$enumerate$class *$class;
  $Iterator it;
  int nxt;
};

extern struct $Iterator$enumerate$class $Iterator$enumerate$methods;
$Iterator$enumerate $Iterator$enumerate$new($Iterator,$int);

$Iterator $enumerate($Iterable wit, $WORD iter, $int start);

// filter ////////////////////////////////////////////////////////////

struct $Iterator$filter;
typedef struct $Iterator$filter *$Iterator$filter;

struct $Iterator$filter$class {
  char *$GCINFO;
  int $class_id;
  $Super$class $superclass;
  void (*__init__)($Iterator$filter, $Iterator, $function);
  void (*__serialize__)($Iterator$filter,$Serial$state);
  $Iterator$filter (*__deserialize__)($Iterator$filter,$Serial$state);
  $bool (*__bool__)($Iterator$filter);
  $str (*__str__)($Iterator$filter);
  $WORD(*__next__)($Iterator$filter);
};

struct $Iterator$filter {
  struct $Iterator$filter$class *$class;
  $Iterator it;
  $function f;
};

extern struct $Iterator$filter$class $Iterator$filter$methods;
$Iterator$filter $Iterator$filter$new($Iterator, $function);

$Iterator $filter($Iterable wit, $function, $WORD iter);

// map ////////////////////////////////////////////////////////////

struct $Iterator$map;
typedef struct $Iterator$map *$Iterator$map;

struct $Iterator$map$class {
  char *$GCINFO;
  int $class_id;
  $Super$class $superclass;
  void (*__init__)($Iterator$map, $Iterator, $function);
  void (*__serialize__)($Iterator$map,$Serial$state);
  $Iterator$map (*__deserialize__)($Iterator$map,$Serial$state);
  $bool (*__bool__)($Iterator$map);
  $str (*__str__)($Iterator$map);
  $WORD(*__next__)($Iterator$map);
};

struct $Iterator$map {
  struct $Iterator$map$class *$class;
  $Iterator it;
  $function f;
};

extern struct $Iterator$map$class $Iterator$map$methods;
$Iterator$map $Iterator$map$new($Iterator, $function);

$Iterator $map($Iterable wit, $function, $WORD iter);


// zip ////////////////////////////////////////////////////////////

struct $Iterator$zip;
typedef struct $Iterator$zip *$Iterator$zip;

struct $Iterator$zip$class {
  char *$GCINFO;
  int $class_id;
  $Super$class $superclass;
  void (*__init__)($Iterator$zip, $Iterator, $Iterator);
  void (*__serialize__)($Iterator$zip,$Serial$state);
  $Iterator$zip (*__deserialize__)($Iterator$zip,$Serial$state);
  $bool (*__bool__)($Iterator$zip);
  $str (*__str__)($Iterator$zip);
  $WORD(*__next__)($Iterator$zip);
};

struct $Iterator$zip {
  struct $Iterator$zip$class *$class;
  $Iterator it1;
  $Iterator it2;
};

extern struct $Iterator$zip$class $Iterator$zip$methods;
$Iterator$zip $Iterator$zip$new($Iterator, $Iterator);

$Iterator $zip($Iterable wit1, $Iterable wit2, $WORD iter1, $WORD iter2);


// EqOpt //////////////////////////////////////////////////////

struct $EqOpt;
typedef struct $EqOpt *$EqOpt;

struct $EqOpt$class {
    char *$GCINFO;
    int $class_id;
    $Super$class $superclass;
    void (*__init__)($EqOpt, $Eq);
    $bool (*__eq__)($EqOpt, $WORD, $WORD);
    $bool (*__ne__)($EqOpt, $WORD, $WORD);
};

struct $EqOpt {
    struct $EqOpt$class *$class;
    $Eq w$Eq$A;
};

$EqOpt $EqOpt$new($Eq);


// Various small functions //////////////////////////////////////////////////////////

$WORD $min($Ord wit, $Iterable wit2, $WORD iter, $WORD deflt);
$WORD $max($Ord wit, $Iterable wit2, $WORD iter, $WORD deflt);

// Signatures generated by actonc 

$WORD $abs ($Number, $Real, $WORD);
$bool $all ($Iterable, $WORD);
$bool $any ($Iterable, $WORD);
$tuple $divmod ($Integral, $WORD, $WORD);
$int $hash ($Hashable, $WORD);
$Iterator $iter ($Iterable, $WORD);
$int $len ($Collection, $WORD);
$WORD $next ($Iterator);
$WORD $pow ($Number, $WORD, $WORD);
$Iterator $reversed ($Sequence, $WORD);
$WORD $round ($Real, $WORD, $int);

$list $replicate($int, $WORD);
