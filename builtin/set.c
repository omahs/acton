#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>
#include <errno.h>
#include <string.h> /*memset*/

#include "builtin.h"

#define DISCARD_NOTFOUND 0
#define DISCARD_FOUND 1

/* 
This implementation of sets is an adaptaation of CPython's set implementation.
*/

// Method tables //////////////////////////////////////////////////////////////////////////////////////////////////

$bool $set_eq_instance( Eq$__class__ cl, $WORD a, $WORD b);
$bool $set_neq_instance( Eq$__class__ cl, $WORD a, $WORD b);

$bool $set_lt_instance(Ord$__class__, $WORD a, $WORD b);
$bool $set_le_instance(Ord$__class__, $WORD a, $WORD b);
$bool $set_gt_instance(Ord$__class__, $WORD a, $WORD b);
$bool $set_ge_instance(Ord$__class__, $WORD a, $WORD b);

$WORD $set_and_instance(Logical$__class__ cl, $WORD a, $WORD b);
$WORD $set_or_instance(Logical$__class__ cl, $WORD a, $WORD b);
$WORD $set_xor_instance(Logical$__class__ cl, $WORD a, $WORD b);

$bool $set_isdisjoint_instance(Set$__class__, $WORD, $WORD);
void $set_add_instance(Set$__class__, $WORD, $WORD);
void $set_discard_instance(Set$__class__, $WORD, $WORD);
$WORD $set_pop_instance(Set$__class__, $WORD);

Iterator $set_iter_instance(Iterable$__class__ cl,$WORD self);
Iterator $set_iter_entry_instance(Iterable$__class__ cl, $WORD self);
$WORD $set_next_instance(Iterator$__class__ cl, $WORD self);

Collection $set_fromiter_instance(Collection$__class__ cl, Iterable it);
$int $set_len_instance(Collection$__class__ cl, $WORD self);

$WORD $set_sub_instance(Minus$__class__ cl, $WORD a, $WORD b);

$bool $set_contains_instance (Container_Eq$__class__ cl, $WORD self, $WORD elem);
$bool $set_containsnot_instance (Container_Eq$__class__ cl, $WORD self, $WORD elem);

static struct Eq$__class__ Eq$set_struct = {"GC_Eq",$set_eq_instance,$set_neq_instance};
Eq$__class__ Eq$set_instance = &Eq$set_struct;

static struct Ord$__class__ Ord$set_struct = {"GC_Ord",&Eq$set_struct,$set_lt_instance ,$set_le_instance ,$set_gt_instance, $set_ge_instance};
Ord$__class__ Ord$set_instance = &Ord$set_struct;

static struct Logical$__class__ Logical$set_struct = {"GC_Logical",$set_and_instance ,$set_or_instance ,$set_xor_instance};
Logical$__class__ Logical$set_instance = &Logical$set_struct;

static struct Minus$__class__ Minus$set_struct = {"GC_Minus",$set_sub_instance};
Minus$__class__ Minus$set_instance = &Minus$set_struct;

static struct Iterator$__class__ Iterator$set_struct = {"GC_Iterator",$set_next_instance};
Iterator$__class__ Iterator$set_instance = &Iterator$set_struct;

static struct Iterable$__class__ Iterable$set_struct = {"GC_Iterable", $set_iter_instance};
Iterable$__class__ Iterable$set_instance = &Iterable$set_struct;

static struct Collection$__class__ Collection$set_struct = {"GC_Collection", &Iterable$set_struct, $set_fromiter_instance, $set_len_instance};
Collection$__class__ Collection$set_instance = &Collection$set_struct;

static struct Container_Eq$__class__ Container_Eq$set_struct = {"GC_Container_Eq",&Collection$set_struct, $set_contains_instance,$set_containsnot_instance,NULL};
Container_Eq$__class__ Container_Eq$set_instance = &Container_Eq$set_struct;

static struct Set$__class__ Set$set_struct = {"GC_Set", &Eq$set_struct,  &Ord$set_struct,  &Logical$set_struct,  &Minus$set_struct,  &Container_Eq$set_struct,
                                              $set_isdisjoint_instance, $set_add_instance, $set_discard_instance, $set_pop_instance};
Set$__class__ Set$set_instance = &Set$set_struct;

// Types ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef struct {
  char *$GCINFO;
  $WORD key;
  long hash;    
} $setentry;

typedef void *$set$__methods__;       // All set methods are from protocols
// Maybe we should  offer union, intersection and symmetric difference under those names.

typedef struct $set {
  char *$GCINFO;
  $set$__methods__ __class__;
  long numelements;    // nr of elements in $set
  long fill;           // numelements + #dummy entries
    /* The table contains mask + 1 slots, and that's a power of 2.
     * We store the mask instead of the size because the mask is more
     * frequently needed.
     */
  long mask;
  long finger;                       // Search finger for pop() 
  Hashable$__class__  h;             // eq and hash function used in this $set
  $setentry *table;                  // the hashtable
} *$set_internal_t;

#define PERTURB_SHIFT 5
#define MIN_SIZE 8

static $WORD _dummy;
#define dummy (&_dummy)

static void $set_insert_clean($setentry *table, long mask, $WORD *key, long hash) {
    $setentry *entry;
    long perturb = hash;
    long i = hash & mask;
    long j;

    while (1) {
        entry = &table[i];
        if (entry->key == NULL)
            goto found_null;
        
        perturb >>= PERTURB_SHIFT;
        i = (i * 5 + 1 + perturb) & mask;
    }
  found_null:
    entry->key = key;
    entry->hash = hash;
}

static int $set_table_resize($set so, int minsize) {
    $setentry *oldtable, *newtable, *entry;
    long oldmask = so->mask;
    long newmask;

    /* Find the smallest table size > minused. */
    long newsize = MIN_SIZE;
    while (newsize <= (long)minsize) {
        newsize <<= 1; // The largest possible value is PY_SSIZE_T_MAX + 1.
    }
    /* Get space for a new table. */
    oldtable = so->table;

    newtable = malloc(sizeof($setentry) * newsize);
    if (newtable == NULL) {
      return -1;
    }

    /* Make the $set empty, using the new table. */
    memset(newtable, 0, sizeof($setentry) * newsize);
    so->mask = newsize - 1;
    so->table = newtable;

    /* Copy the data over; 
       dummy entries aren't copied over, of course */
    newmask = (long)so->mask;
    if (so->fill == so->numelements) {
        for (entry = oldtable; entry <= oldtable + oldmask; entry++) {
            if (entry->key != NULL) {
                $set_insert_clean(newtable, newmask, entry->key, entry->hash);
            }
        }
    } else {
        so->fill = so->numelements;
        for (entry = oldtable; entry <= oldtable + oldmask; entry++) {
            if (entry->key != NULL && entry->key != dummy) {
                $set_insert_clean(newtable, newmask, entry->key, entry->hash);
            }
        }
    }

    free(oldtable);
    return 0;
}

static $setentry *$set_lookkey($set set, $WORD key, long hash) {
    $setentry *entry;
    long perturb;
    long mask = set->mask;
    long i = hash & mask;

    entry = &set->table[i];
    if (entry->key == NULL)
        return entry;

    perturb = hash;

    while (1) {
        if (entry->hash == hash) {
            $WORD *startkey = entry->key;
            // startkey cannot be a dummy because the dummy hash field is -1 
            // assert(startkey != dummy);
            if (startkey == key || set->h->Eq$__methods__->__eq__(set->h->Eq$__methods__,startkey,key))
              return entry;
        }
        perturb >>= PERTURB_SHIFT;
        i = (i * 5 + 1 + perturb) & mask;

        entry = &set->table[i];
        if (entry->key == NULL)
            return entry;
    }
}

static int $set_contains_entry($set set, $WORD elem, long hash) {
  return $set_lookkey(set, elem, hash)->key != NULL;
}

$set $set_new(Hashable$__class__ h) {
  $set res = malloc(sizeof(struct $set));
  // $set_internal_t res = malloc(sizeof(char*) + 4*sizeof(long)+sizeof(Hashable$__class__)+sizeof($setentry*));
  res->numelements = 0;
  res->fill = 0;
  res->mask = MIN_SIZE-1;
  res->finger = 0;
  res->h = h;
  res->table = malloc(MIN_SIZE*sizeof($setentry));
  memset(res->table,0,MIN_SIZE*sizeof($setentry));
  res->__class__ = NULL;
  return res; 
}


static void $set_add_entry($set set, $WORD key, long hash) {
  $setentry *freeslot;
  $setentry *entry;
  long perturb;
  long mask;
  long i;                       // Unsigned for defined overflow behavior 
  mask = set->mask;
  i = hash & mask;

  entry = &set->table[i];
  if (entry->key == NULL)
    goto found_unused;

  freeslot = NULL;
  perturb = hash;

  while (1) {
    if (entry->hash == hash) {
      $WORD startkey = entry->key;
      // startkey cannot be a dummy because the dummy hash field is -1 
      if (startkey == key || set->h->Eq$__methods__->__eq__(set->h->Eq$__methods__,startkey,key))
          goto found_active;
          }
      else if (entry->hash == -1)
        freeslot = entry;

      perturb >>= PERTURB_SHIFT;
      i = (i * 5 + 1 + perturb) & mask;

      entry = &set->table[i];
      if (entry->key == NULL)
        goto found_unused_or_dummy;
    }

  found_unused_or_dummy:
    if (freeslot == NULL)
      goto found_unused;
    set->numelements++;
    freeslot->key = key;
    freeslot->hash = hash;
    return;

  found_unused:
    set->fill++;
    set->numelements++;
    entry->key = key;
    entry->hash = hash;
    if ((size_t)set->fill*5 < mask*3)
      return;
    $set_table_resize(set, set->numelements>50000 ? set->numelements*2 : set->numelements*4);
    return;
  found_active:
    return;
}


static $set $set_copy($set set) {
  $set res = $set_new(set->h);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,set);
  $WORD w;
  while((w = next(iter))){
    $WORD key = (($setentry*)w)->key;
    long hash = (($setentry*)w)->hash;
    $set_add_entry(res,key,hash);
  }
  return res;
}

static int $set_discard_entry($set set, $WORD elem, long hash) {
  $setentry *entry = $set_lookkey(set, elem, hash);
  if (entry->key != NULL) {
    entry->key = dummy;
    entry->hash = -1;
    set->numelements--;
    return DISCARD_FOUND;
  } else
    return DISCARD_NOTFOUND;
}


// Eq //////////////////////////////////////////////////////////////////////////////////////////////


$bool $set_eq($set set, $set other) {
  if (set == other) 
    return 1;
  if (set->numelements != other->numelements)
    return 0;
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    if(!$set_contains_entry(set, (($setentry*)w)->key, (($setentry*)w)->hash))
      return 0;
  }
  return 1;
}

// instance methods

$bool $set_eq_instance(Eq$__class__ cl, $WORD a, $WORD b) {
  return $set_eq(a,b);
}

$bool $set_neq_instance(Eq$__class__ cl, $WORD a, $WORD b) {
  return !$set_eq(a,b);
}

// Ord /////////////////////////////////////////////////////////////////////////////////////////////

$bool $set_ge($set set, $set other) {
  if (set == other) 
    return 1;    
  if (set->numelements < other->numelements)
    return 0;
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    if(!$set_contains_entry(set, (($setentry*)w)->key, (($setentry*)w)->hash))
      return 0;
  }
  return 1;
}

$bool $set_gt($set set, $set other) {
  if (set == other) 
    return 0;    
  if (set->numelements <= other->numelements)
    return 0;
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    if(!$set_contains_entry(set, (($setentry*)w)->key, (($setentry*)w)->hash))
      return 0;
  }
  return 1;
}

$bool $set_le($set set, $set other) {
  return $set_ge(other,set);
}

$bool $set_lt($set set, $set other) {
  return $set_gt(other,set);
}

// instance methods

$bool $set_lt_instance(Ord$__class__ cl, $WORD a, $WORD b) {
  return $set_lt(a,b);
}

$bool $set_le_instance(Ord$__class__ cl, $WORD a, $WORD b) {
  return $set_le(a,b);
}

$bool $set_gt_instance(Ord$__class__ cl, $WORD a, $WORD b) {
  return $set_gt(a,b);
}

$bool $set_ge_instance(Ord$__class__ cl, $WORD a, $WORD b) {
  return $set_ge(a,b);
}

// Logical /////////////////////////////////////////////////////////////////////////////////////////////


$set $set_intersection($set set, $set other) {
  if (Collection$set_instance->__len__(Collection$set_instance,other) > Collection$set_instance->__len__(Collection$set_instance,set))
    return $set_intersection(other,set);
  $set res = $set_new(set->h);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,set);
  $WORD w;
  while((w = next(iter))){
    $WORD key = (($setentry*)w)->key;
    long hash = (($setentry*)w)->hash;
    if ($set_contains_entry(other,key,hash))
      $set_add_entry(res,key,hash);
  }
  return res;
}


$set $set_union($set set, $set other) {
  if (Collection$set_instance->__len__(Collection$set_instance,other) > Collection$set_instance->__len__(Collection$set_instance,set))
    return $set_union(other,set);
  $set res = $set_copy(set);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    $WORD key = (($setentry*)w)->key;
    long hash = (($setentry*)w)->hash;
    $set_add_entry(res,key,hash);
  }
  return res;
}

$set $set_symmetric_difference($set set, $set other) {
  $set res = $set_copy(set);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    $WORD key = (($setentry*)w)->key;
    long hash = (($setentry*)w)->hash;
    if(!$set_discard_entry(res,key,hash))
      $set_add_entry(res,key,hash);
  }
  return res;
}

// instance methods

$WORD $set_or_instance(Logical$__class__ cl, $WORD a, $WORD b) {
  return $set_union(a,b);
}

$WORD $set_and_instance(Logical$__class__ cl, $WORD a, $WORD b) {
  return $set_intersection(a,b);
}

$WORD $set_xor_instance(Logical$__class__ cl, $WORD a, $WORD b) {
  return $set_symmetric_difference(a,b);
}

// Set /////////////////////////////////////////////////////////////////////////////////////////////

void $set_add($set set, $WORD elem) {
  $set_add_entry(set,elem,*set->h->__hash__(set->h,elem));
}


void $set_discard($set set, $WORD elem) {
  $set_discard_entry(set,elem,*set->h->__hash__(set->h,elem));
}

void $set_remove($set set, $WORD elem) {
  long hash = *set->h->__hash__(set->h,elem);
  if($set_discard_entry(set,elem,hash))
    return;
  else {
      exception e;
      MKEXCEPTION(e,KEYERROR);
      RAISE(e);
  }
}

$WORD $set_pop($set set) {
  $WORD res;
  // Make sure the search finger is in bounds 
  $setentry *entry = set->table + (set->finger & set->mask);
  $setentry *limit = set->table + set->mask;

  if (set->numelements == 0) {
    exception e;
    MKEXCEPTION(e,KEYERROR);
    RAISE(e);
    return NULL;
  }
  while (entry->key == NULL || entry->key==dummy) {
    entry++;
    if (entry > limit)
      entry = set->table;
  }
  res = entry->key;
  entry->key = dummy;
  entry->hash = -1;
  set->numelements--;
  set->finger = entry - set->table + 1;   // next place to start 
  return res;
}

$bool $set_isdisjoint($set set, $set other) {
  if (set == other) 
    return set->numelements == 0;
  if (other->numelements > set->numelements)
    return $set_isdisjoint(other,set);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    if($set_contains_entry(set, (($setentry*)w)->key, (($setentry*)w)->hash))
      return 0;
  }
  return 1;
}

// instance methods

void $set_add_instance(Set$__class__ cl, $WORD self, $WORD elem) {
  $set_add(self,elem);
}

void $set_discard_instance(Set$__class__ cl, $WORD self, $WORD elem) {
  $set_discard(self,elem);
}

$bool $set_isdisjoint_instance(Set$__class__ cl, $WORD self, $WORD other) {
  return $set_isdisjoint(self,other);
}

/*
void $set_remove_instance(Set$__class__ cl, $WORD self, $WORD elem) {
  $set_remove(self,elem);
}
*/

$WORD $set_pop_instance(Set$__class__ cl, $WORD self) {
  return $set_pop(self);
}

// Collection /////////////////////////////////////////////////////////////////////////////////////////////

// What about from_iter; needs an instance of Hashable to create empty set.

$int $set_len($set set) {
  return to$int(set->numelements);
}

//instance methods

$int $set_len_instance(Collection$__class__ cl, $WORD self) {
  return $set_len(self);
}

Collection $set_fromiter_instance(Collection$__class__ cl, Iterable it) {
  exception e;
  MKEXCEPTION(e,NOTIMPLEMENTED);
  RAISE(e);
  return NULL;
}

// Container_Eq ///////////////////////////////////////////////////////////////////////////////////////

int $set_contains($set set, $WORD elem) {
  return $set_contains_entry(set,elem,*set->h->__hash__(set->h,elem));
}

$bool $set_contains_instance(Container_Eq$__class__ cl, $WORD self, $WORD elem) {
  return $set_contains(self, elem);
}

$bool $set_containsnot_instance(Container_Eq$__class__ cl, $WORD self, $WORD elem) {
  return !$set_contains(self, elem);
}

// Iterable ///////////////////////////////////////////////////////////////////////////////////////


typedef struct $set_iterator_struct {
  $set_internal_t src;
  int nxt;
} *$set_iterator_state_t; 

$WORD $set_iterator_next_entry($set_iterator_state_t state) {
  $WORD res;
  $setentry *table = state->src->table;
  long n = state->src->mask;
  long i = state->nxt;
  while (i <= n) {
    $setentry *entry = &table[i];
    if (entry->key != NULL && entry->key != dummy) {
      res = entry;
      state->nxt = i+1;
      return res;
    }
    i++;
  }
  exception e;
  MKEXCEPTION(e,STOPITERATION);
  RAISE(e);
  return NULL;
}

$WORD $set_iterator_next($set_iterator_state_t state) {
  $WORD res, res2;
  if((res2 = $set_iterator_next_entry(state))) {
    res = (($setentry*)res2)->key;
    return res;
  } 
  exception e;
  MKEXCEPTION(e,STOPITERATION);
  RAISE(e);
  return NULL;
}

$set_iterator_state_t $set_state_of($set set) {
  $set_iterator_state_t state = malloc(sizeof(struct $set_iterator_struct));
  state->src = set;
  state->nxt = 0;
  return state;
}

// instance methods

$WORD $set_next_instance(Iterator$__class__ cl, $WORD self) {
  return  $set_iterator_next(self);
}
$WORD $set_next_entry_instance(Iterator$__class__ cl, $WORD self) {
  return  $set_iterator_next_entry(self);
}

Iterator $set_iter_instance(Iterable$__class__ cl, $WORD self) {
  return Iterator$__pack__(Iterator$set_instance,$set_state_of(($set)self));
}

Iterator $set_iter_entry_instance(Iterable$__class__ cl, $WORD self) {
  Iterator$__class__ cl1 = malloc(sizeof(struct Iterator$__class__));
  cl1->$GCINFO = "GC_Iterator$__class__";
  cl1->__next__ = $set_next_entry_instance;
  return Iterator$__pack__(cl1,$set_state_of(($set)self));
}

// Minus ///////////////////////////////////////////////////////////////////////////////////////////

$set $set_difference($set set, $set other) {
  $set res = $set_copy(set);
  Iterator iter = $set_iter_entry_instance(Iterable$set_instance,other);
  $WORD w;
  while((w = next(iter))){
    $WORD key = (($setentry*)w)->key;
    long hash = (($setentry*)w)->hash;
    $set_discard_entry(res,key,hash);
  }
  return res;
}

$WORD $set_sub_instance(Minus$__class__ cl, $WORD a, $WORD b) {
  return $set_difference(a,b);
}