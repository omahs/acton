{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}
module Acton.Kinds(check, kindError) where

import qualified Control.Exception
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Control.Monad.State.Strict
import Control.Monad
import Pretty
import Utils
import Acton.Syntax
import Acton.Names
import Acton.Builtin
import Acton.Subst
import qualified Acton.Env


check                               :: Acton.Env.Env -> Module -> IO Module
check ienv (Module l imps ss)       = return (Module l imps ss1)
  where env                         = kenv0 ienv
        ss1                         = runKindM (kchkTop env ss)


type KVar                           = Name

data KindState                      = KindState {
                                        nextint     :: Int,
                                        currsubst   :: Map KVar Kind,
                                        xvars       :: QBinds
                                      }

type KindM a                        = State KindState a

runKindM                            :: KindM a -> a
runKindM m                          = evalState m $ KindState { nextint = 1, currsubst = Map.empty, xvars = [] }

newUnique                           :: KindM Int
newUnique                           = state $ \st -> (nextint st, st{ nextint = nextint st + 1 })

substitute                          :: KVar -> Kind -> KindM ()
substitute kv k                     = state $ \st -> ((), st{ currsubst = Map.insert kv k (currsubst st)})

getSubstitution                     :: KindM (Map KVar Kind)
getSubstitution                     = state $ \st -> (currsubst st, st)

storeXVar                           :: TVar -> TCon -> KindM ()
storeXVar xv p                      = state $ \st -> ((), st{ xvars = Quant xv [p] : xvars st })

swapXVars                           :: QBinds -> KindM QBinds
swapXVars q                         = state $ \st -> (xvars st, st{ xvars = q })

newWildvar                          = do k <- newKVar
                                         n <- Internal Wildvar "" <$> newUnique
                                         return $ TV k n

newKVar                             = KVar <$> (Internal Kindvar "" <$> newUnique)

newXVar                             = TV KType <$> (Internal Xistvar "" <$> newUnique)


data KEnv                           = KEnv { impenv :: Acton.Env.Env, tcons :: Kinds, tvars :: [TVar] }

type Kinds                          = [(Name,Kind)]

kenv0 ienv                          = KEnv { impenv = ienv, tcons = [], tvars = [] }

extcons ke env                      = env { tcons = ke ++ tcons env }

extvars vs env
  | not $ null clash                = Acton.Env.err1 (head clash) "Type variable already in scope:"    -- No type variable shadowing
  | not $ null dups                 = Acton.Env.err1 (head dups) "Duplicate type variable in binding:"
  | otherwise                       = env { tvars = vs ++ tvars env }
  where clash                       = vs `intersect` tvars env
        dups                        = duplicates vs

tconKind (NoQ n) env                = case lookup n (tcons env) of
                                        Just k  -> k
                                        Nothing -> Acton.Env.tconKind (NoQ n) (impenv env)
tconKind qn env                     = Acton.Env.tconKind qn (impenv env)

tvarKind v env                      = case filter (==v) (tvars env) of
                                        [] -> Acton.Env.err1 v "Unbound type variable:"
                                        TV k _ : _ -> k

instance Pretty (Name,Kind) where
    pretty (n,k)                    = pretty n <+> colon <+> pretty k


autoQuantS env (TSchema l q t)      = TSchema l (q ++ auto_q) t
  where auto_q                      = map quant $ nub (tyfree q ++ tyfree t) \\ (tvSelf : tybound q ++ tvars env)

autoQuantD env (Def l n q p k t b d x)
                                    = Def l n (q ++ auto_q) p k t b d x
  where auto_q                      = map quant $ nub (tyfree p ++ tyfree k ++ tyfree t) \\ (tvSelf : tybound q ++ tvars env)
autoQuantD env d                    = d


--                  TWild             ~TWild
--                ---------------------------------------------------
--         Exist  | Def             | TSchema                        |
--                ---------------------------------------------------
--        ~Exist  | Lambda,Pattern  | Actor,Class,Protocol,Extension |
--                ---------------------------------------------------


----------------------------------------------------------------------------------------------------------------------
-- instKWild
----------------------------------------------------------------------------------------------------------------------

class InstKWild a where
    instKWild                       :: a -> KindM a

instance (InstKWild a) => InstKWild [a] where
    instKWild                       = mapM instKWild
    
instance InstKWild Decl where
    instKWild d                     = do q <- instKWild (qbinds d); return d{ qbinds = q }

instance InstKWild QBind where
    instKWild (Quant v us)          = Quant <$> instKWild v <*> return us

instance InstKWild TSchema where
    instKWild (TSchema l q t)       = TSchema l <$> instKWild q <*> return t

instance InstKWild TVar where
    instKWild (TV KWild n)          = TV <$> newKVar <*> return n
    instKWild v                     = return v


----------------------------------------------------------------------------------------------------------------------
-- convTWild
----------------------------------------------------------------------------------------------------------------------

class ConvTWild a where
    convTWild                       :: a -> KindM a

instance ConvTWild Type where
    convTWild (TWild l)             = TVar l <$> newWildvar
    convTWild (TFun l e p k t)      = TFun l <$> convTWild e <*> convTWild p <*> convTWild k <*> convTWild t
    convTWild (TTuple l p k)        = TTuple l <$> convTWild p <*> convTWild k
    convTWild (TOpt l t)            = TOpt l <$> convTWild t
    convTWild (TCon l c)            = TCon l <$> convTWild c
    convTWild (TRow l k n t r)      = TRow l k n <$> convTWild t <*> convTWild r
    convTWild (TFX l (FXMut t))     = TFX l <$> FXMut <$> convTWild t
    convTWild (TFX l (FXAct t))     = TFX l <$> FXMut <$> convTWild t
    convTWild t                     = return t

instance ConvTWild TCon where
    convTWild (TC n ts)             = TC n <$> mapM convTWild ts

instance ConvTWild QBinds where
    convTWild q                     = mapM instq q
      where instq (Quant v us)      = Quant v <$> mapM convTWild us

instance (ConvTWild a) => ConvTWild (Maybe a) where
    convTWild t                     = sequence (fmap convTWild t)

instance ConvTWild PosPar where
    convTWild (PosPar n t e p)      = PosPar n <$> convTWild t <*> return e <*> convTWild p
    convTWild (PosSTAR n t)         = PosSTAR n <$> convTWild t
    convTWild PosNIL                = return PosNIL
    
instance ConvTWild KwdPar where
    convTWild (KwdPar n t e k)      = KwdPar n <$> convTWild t <*> return e <*> convTWild k
    convTWild (KwdSTAR n t)         = KwdSTAR n <$> convTWild t
    convTWild KwdNIL                = return KwdNIL


----------------------------------------------------------------------------------------------------------------------
-- convPExist
----------------------------------------------------------------------------------------------------------------------

class ConvPExist a where
    convPExist                      :: KEnv -> a -> KindM a

instance ConvPExist Type where
    convPExist env (TCon l c)       = do c <- convPExist env c
                                         case khead $ tconKind (tcname c) env of
                                             KProto -> do
                                                 xv <- newXVar
                                                 storeXVar xv c
                                                 return $ TVar l xv
                                             _ ->
                                                 return $ TCon l c
      where khead (KFun _ k)        = k
            khead k                 = k
    convPExist env (TFun l e p k t) = TFun l <$> convPExist env e <*> convPExist env p <*> convPExist env k <*> convPExist env t
    convPExist env (TTuple l p k)   = TTuple l <$> convPExist env p <*> convPExist env k
    convPExist env (TOpt l t)       = TOpt l <$> convPExist env t
    convPExist env (TRow l k n t r) = TRow l k n <$> convPExist env t <*> convPExist env r
    convPExist env t                = return t

instance ConvPExist TCon where
    convPExist env (TC n ts)        = TC n <$> mapM (convPExist env) ts

instance ConvPExist QBinds where
    convPExist env q                = mapM instq q
      where instq (Quant v us)      = Quant v <$> mapM (convPExist env) us

instance (ConvPExist a) => ConvPExist (Maybe a) where
    convPExist env t                = sequence $ fmap (convPExist env) t

instance ConvPExist PosPar where
    convPExist env (PosPar n t e p) = PosPar n <$> convPExist env t <*> return e <*> convPExist env p
    convPExist env (PosSTAR n t)    = PosSTAR n <$> convPExist env t
    convPExist env PosNIL           = return PosNIL
    
instance ConvPExist KwdPar where
    convPExist env (KwdPar n t e k) = KwdPar n <$> convPExist env t <*> return e <*> convPExist env k
    convPExist env (KwdSTAR n t)    = KwdSTAR n <$> convPExist env t
    convPExist env KwdNIL           = return KwdNIL


----------------------------------------------------------------------------------------------------------------------
-- kchk
----------------------------------------------------------------------------------------------------------------------

kchkTop env ss                      = do ss <- kchkSuite env ss
                                         ksubst True ss

class KCheck a where
    kchk                            :: KEnv -> a -> KindM a

instance KCheck a => KCheck [a] where
    kchk env                        = mapM (kchk env)

instance KCheck a => KCheck (Maybe a) where
    kchk env                        = traverse (kchk env)

kchkSuite env []                    = return []
kchkSuite env (Decl l ds : ss)      = do ds <- instKWild (map (autoQuantD env) ds)
                                         let env1 = extcons (concatMap kinds ds) env
                                         ds <- kchk env1 ds
                                         ss <- kchkSuite env1 ss
                                         return (Decl l ds : ss)
  where kinds (Actor _ n q _ _ _)   = [(n,kind KType q)]
        kinds (Class _ n q _ _)     = [(n,kind KType q)]
        kinds (Protocol _ n q _ _)  = [(n,kind KProto q)]
        kinds _                     = []
        kind k []                   = k
        kind k q                    = KFun [ tvkind v | Quant v _ <- q ] k
kchkSuite env (s : ss)              = do s <- kchk env s; ss <- kchkSuite env ss; return (s:ss)

instance KCheck Stmt where
    kchk env (Expr l e)             = Expr l <$> kchk env e
    kchk env (Assign l ps e)        = Assign l <$> kchk env ps <*> kchk env e
    kchk env (MutAssign l t e)      = MutAssign l <$> kchk env t <*> kchk env e
    kchk env (AugAssign l t op e)   = AugAssign l <$> kchk env t <*> return op <*> kchk env e
    kchk env (Assert l e mbe)       = Assert l <$> kchk env e <*> kchk env mbe
    kchk env (Pass l)               = return $ Pass l
    kchk env (Delete l t)           = Delete l <$> kchk env t
    kchk env (Return l mbe)         = Return l <$> kchk env mbe
    kchk env (Raise l mbex)         = Raise l <$> kchk env mbex
    kchk env (Break l)              = return $ Break l
    kchk env (Continue l)           = return $ Continue l
    kchk env (If l bs els)          = If l <$> kchk env bs <*> kchkSuite env els
    kchk env (While l e b els)      = While l <$> kchk env e <*> kchkSuite env b <*> kchkSuite env els
    kchk env (For l p e b els)      = For l <$> kchk env p <*> kchk env e <*> kchkSuite env b <*> kchkSuite env els
    kchk env (Try l b hs els fin)   = Try l <$> kchkSuite env b <*> kchk env hs <*> kchkSuite env els <*> kchkSuite env fin
    kchk env (With l is b)          = With l <$> kchk env is <*> kchkSuite env b
    kchk env (Data l mbt ss)        = Data l <$> kchk env mbt <*> kchkSuite env ss
    kchk env (VarAssign l ps e)     = VarAssign l <$> kchk env ps <*> kchk env e
    kchk env (After l e e')         = After l <$> kchk env e <*> kchk env e'
    kchk env (Decl l ds)            = Decl l <$> kchk env ds
    kchk env (Signature l ns sc d)  = Signature l ns <$> (kchk env =<< instKWild (autoQuantS env sc)) <*> return d

instance KCheck Decl where
    kchk env (Def l n q p k t b d x)
                                    = do tmp <- swapXVars []
                                         q <- convPExist env =<< convTWild q
                                         p <- convPExist env =<< convTWild p
                                         k <- convPExist env =<< convTWild k
                                         t <- convPExist env =<< convTWild t
                                         x <- convPExist env =<< convTWild x
                                         q' <- swapXVars tmp
                                         let env1 = extvars (tybound (q++q')) env
                                         q <- kchkQBinds env1 (q++q')
                                         p <- kchk env1 p
                                         k <- kchk env1 k
                                         t <- kexp KType env1 t
                                         x <- kexp KFX env1 x
                                         b <- kchkSuite env1 b
                                         return $ Def l n q p k t b d x
    kchk env (Actor l n q p k b)    = Actor l n <$> kchkQBinds env1 q <*> kchk env1 p <*> kchk env1 k <*> kchkSuite env1 b
      where env1                    = extvars (tybound q) env
    kchk env (Class l n q us b)     = Class l n <$> kchkQBinds env1 q <*> kchkBounds env1 us <*> kchkSuite env1 b
      where env1                    = extvars (tvSelf : tybound q) env
    kchk env (Protocol l n q us b)  = Protocol l n <$> kchkQBinds env1 q <*> kchkPBounds env1 us <*> kchkSuite env1 b
      where env1                    = extvars (tvSelf : tybound q) env
    kchk env (Extension l n q us b) = do kexp KType env1 (TC n (map tVar $ tybound q))
                                         Extension l n <$> kchkQBinds env1 q <*> kchkPBounds env1 us <*> kchkSuite env1 b
      where env1                    = extvars (tvSelf : tybound q) env

instance KCheck Expr where
    kchk env (Var l n)              = return $ Var l n
    kchk env (Int l i s)            = return $ Int l i s
    kchk env (Float l f s)          = return $ Float l f s
    kchk env (Imaginary l i s)      = return $ Imaginary l i s
    kchk env (Bool l b)             = return $ Bool l b
    kchk env (None l)               = return $ None l
    kchk env (NotImplemented l)     = return $ NotImplemented l
    kchk env (Ellipsis l)           = return $ Ellipsis l
    kchk env (Strings l ss)         = return $ Strings l ss
    kchk env (BStrings l ss)        = return $ BStrings l ss
    kchk env (Call l e [] ps ks)    = Call l <$> kchk env e <*> pure [] <*> kchk env ps <*> kchk env ks
    kchk env (Index l e is)         = Index l <$> kchk env e <*> kchk env is
    kchk env (Slice l e sl)         = Slice l <$> kchk env e <*> kchk env sl
    kchk env (Cond l e1 e2 e3)      = Cond l <$> kchk env e1 <*> kchk env e2 <*> kchk env e3
    kchk env (BinOp l e1 op e2)     = BinOp l <$> kchk env e1 <*> return op <*> kchk env e2
    kchk env (CompOp l e ops)       = CompOp l <$> kchk env e <*> kchk env ops
    kchk env (UnOp l op e)          = UnOp l op <$> kchk env e 
    kchk env (Dot l e n)            = Dot l <$> kchk env e <*> return n
    kchk env (DotI l e i tl)        = DotI l <$> kchk env e <*> return i <*> return tl
    kchk env (Lambda l p k e x)     = Lambda l <$> (kchk env =<< convTWild p) <*> (kchk env =<< convTWild k) <*> kchk env e <*> kexp KFX env x
    kchk env (Yield l e)            = Yield l <$> kchk env e
    kchk env (YieldFrom l e)        = YieldFrom l <$> kchk env e
    kchk env (Tuple l es ks)        = Tuple l <$> kchk env es <*> kchk env ks
    kchk env (List l es)            = List l <$> kchk env es
    kchk env (ListComp l e c)       = ListComp l <$> kchk env e <*> kchk env c
    kchk env (Dict l as)            = Dict l <$> kchk env as
    kchk env (DictComp l a c)       = DictComp l <$> kchk env a <*> kchk env c
    kchk env (Set l es)             = Set l <$> kchk env es
    kchk env (SetComp l e c)        = SetComp l <$> kchk env e <*> kchk env c
    kchk env (Paren l e)            = Paren l <$> kchk env e

instance KCheck Pattern where
    kchk env (PVar l n t)           = PVar l n <$> (kexp KType env =<< convTWild t)
    kchk env (PTuple l ps ks)       = PTuple l <$> kchk env ps <*> kchk env ks
    kchk env (PList l ps p)         = PList l <$> kchk env ps <*> kchk env p
    kchk env (PParen l p)           = PParen l <$> kchk env p

instance KCheck Exception where
    kchk env (Exception e mbe)      = Exception <$> kchk env e <*> kchk env mbe

instance KCheck Branch where
    kchk env (Branch e ss)          = Branch <$> kchk env e <*> kchkSuite env ss

instance KCheck Handler where
    kchk env (Handler ex b)         = Handler <$> kchk env ex <*> kchkSuite env b

instance KCheck Except where
    kchk env (ExceptAll l)          = return $ ExceptAll l
    kchk env (Except l x)           = do kexp KType env (TC x []); return $ Except l x
    kchk env (ExceptAs l x n)       = do kexp KType env (TC x []); return $ ExceptAs l x n

instance KCheck PosPar where
    kchk env (PosPar n t e p)       = PosPar n <$> kexp KType env t <*> kchk env e <*> kchk env p
    kchk env (PosSTAR n t)          = PosSTAR n <$> kexp KType env t
    kchk env PosNIL                 = return PosNIL
    
instance KCheck KwdPar where
    kchk env (KwdPar n t e k)       = KwdPar n <$> kexp KType env t <*> kchk env e <*> kchk env k
    kchk env (KwdSTAR n t)          = KwdSTAR n <$> kexp KType env t
    kchk env KwdNIL                 = return KwdNIL
    
instance KCheck PosArg where
    kchk env (PosArg e p)           = PosArg <$> kchk env e <*> kchk env p
    kchk env (PosStar e)            = PosStar <$> kchk env e
    kchk env PosNil                 = return PosNil
    
instance KCheck KwdArg where
    kchk env (KwdArg n e k)         = KwdArg n <$> kchk env e <*> kchk env k
    kchk env (KwdStar e)            = KwdStar <$> kchk env e
    kchk env KwdNil                 = return KwdNil
    
instance KCheck PosPat where
    kchk env (PosPat p ps)          = PosPat <$> kchk env p <*> kchk env ps
    kchk env (PosPatStar p)         = PosPatStar <$> kchk env p
    kchk env PosPatNil              = return PosPatNil
    
instance KCheck KwdPat where
    kchk env (KwdPat n p ps)        = KwdPat n <$> kchk env p <*> kchk env ps
    kchk env (KwdPatStar p)         = KwdPatStar <$> kchk env p
    kchk env KwdPatNil              = return KwdPatNil
    
instance KCheck OpArg where
    kchk env (OpArg op e)           = OpArg op <$> kchk env e

instance KCheck Comp where
    kchk env (CompFor l p e c)      = CompFor l <$> kchk env p <*> kchk env e <*> kchk env c
    kchk env (CompIf l e c)         = CompIf l <$> kchk env e <*> kchk env c
    kchk env NoComp                 = return NoComp

instance KCheck WithItem where
    kchk env (WithItem e p)         = WithItem <$> kchk env e <*> kchk env p

instance KCheck Elem where
    kchk env (Elem e)               = Elem <$> kchk env e
    kchk env (Star e)               = Star <$> kchk env e

instance KCheck Assoc where
    kchk env (Assoc e1 e2)          = Assoc <$> kchk env e1 <*> kchk env e2
    kchk env (StarStar e)           = StarStar <$> kchk env e
  
instance KCheck Sliz where
    kchk env (Sliz l e1 e2 e3)      = Sliz l <$> kchk env e1 <*> kchk env e2 <*> kchk env e3

instance KCheck TSchema where
    kchk env (TSchema l q t)
      | not $ null ambig            = Acton.Env.err2 ambig "Ambiguous type variable in schema:"
      | otherwise                   = do tmp <- swapXVars []
                                         q <- convPExist env q
                                         t <- convPExist env t
                                         q' <- swapXVars tmp
                                         let env1 = extvars (tybound (q++q')) env
                                         q <- kchkQBinds env1 (q++q')
                                         t <- kexp KType env1 t
                                         return $ TSchema l q t
      where ambig                   = tybound q \\ tyfree t

kchkQBinds env []                   = return []
kchkQBinds env (Quant v us : q)     = do us <- kchkBounds env us
                                         q <- kchkQBinds env q
                                         return $ Quant v us : q

kchkBounds env []                   = return []
kchkBounds env (u:us)               = do (k,u) <- kinfer env u
                                         case k of
                                            KProto -> (:) u <$> kchkPBounds env us
                                            _ -> do kunify (loc u) k KType; (:) u <$> kchkPBounds env us
    
kchkPBounds env us                  = mapM (kexp KProto env) us


----------------------------------------------------------------------------------------------------------------------
-- kinfer
----------------------------------------------------------------------------------------------------------------------

class KInfer t where
    kinfer                          :: KEnv -> t -> KindM (Kind,t)


instance (KInfer t) => KInfer (Maybe t) where
    kinfer env Nothing              = do k <- newKVar; return (k, Nothing)
    kinfer env (Just t)             = do (k,t) <- kinfer env t; return (k, Just t)

instance KInfer TVar where
    kinfer env tv                   = do tv <- instKWild tv
                                         return (tvkind tv, tv)

instance KInfer TCon where
    kinfer env (TC n [])            = return (tconKind n env, TC n [])
    kinfer env (TC n ts)            = do let kn = tconKind n env
                                         (ks,ts) <- fmap unzip $ mapM (kinfer env) ts
                                         k <- newKVar
                                         kunify (loc n) kn (KFun ks k)
                                         k <- ksubst False k
                                         return (k, TC n ts)

generated (TV k n)  = case n of
                        Internal Kindvar _ _ -> True
                        Internal Typevar _ _ -> True
                        Internal Wildvar _ _ -> True
                        _                    -> False

--generated (TV k n)  = case n of
--                        Name{} -> False
--                        _      -> True


instance KInfer Type where
    kinfer env (TWild l)            = Acton.Env.err1 l "Illegal wildcard type"
    kinfer env (TVar l v)           = do (k,v) <- kinfer env v
                                         when (not $ generated v) $ kunify l k (tvarKind v env)     -- Generated TVars are not int the environment
                                         return (k, TVar l v)
    kinfer env (TCon l c)           = do c <- kexp KType env c
                                         return (KType, TCon l c)
    kinfer env (TFun l fx p k t)    = do fx <- kexp KFX env fx
                                         p <- kexp PRow env p
                                         k <- kexp KRow env k
                                         t <- kexp KType env t
                                         return (KType, TFun l fx p k t)
    kinfer env (TTuple l p k)       = do p <- kexp PRow env p
                                         k <- kexp KRow env k
                                         return (KType, TTuple l p k)
    kinfer env (TUnion l us)        = return (KType, TUnion l $ Acton.Env.uniNorm (impenv env) l us)
    kinfer env (TOpt _ t@TOpt{})    = kinfer env t
    kinfer env (TOpt l t)           = do t <- kexp KType env t
                                         return (KType, TOpt l t)
    kinfer env (TNone l)            = return (KType, TNone l)
    kinfer env (TNil l k)           = return (k, TNil l k)
    kinfer env (TRow l k n t r)     = do t <- kexp KType env t
                                         r <- kexp k env r
                                         return (k, TRow l k n t r)
    kinfer env (TFX l fx)           = do fx <- kchk env fx
                                         return (KFX, TFX l fx)

instance KCheck FX where
    kchk env (FXAction)             = return FXAction
    kchk env (FXAct t)              = FXAct <$> kexp KType env t
    kchk env (FXMut t)              = FXMut <$> kexp KType env t
    kchk env (FXPure)               = return FXPure

kexp k env t                        = do (k',t) <- kinfer env t
                                         kunify (loc t) k' k
                                         return t

----------------------------------------------------------------------------------------------------------------------
-- kunify
----------------------------------------------------------------------------------------------------------------------

kunify l k1 k2                      = do k1 <- ksubst False k1; k2 <- ksubst False k2; kunify' l k1 k2

kunify' l (KVar v1) (KVar v2)
  | v1 == v2                        = return ()
kunify' l (KVar v) k2               = do when (v `elem` kfree k2) (infiniteKind l v k2)
                                         substitute v k2
kunify' l k1 (KVar v)               = do when (v `elem` kfree k1) (infiniteKind l v k1)
                                         substitute v k1
kunify' l (KFun ks1 k1) (KFun ks2 k2)
  | length ks1 == length ks2        = do mapM_ (uncurry $ kunify l) (ks1 `zip` ks2)
                                         kunify l k1 k2
kunify' l k1 k2
  | k1 == k2                        = return ()
  | otherwise                       = noUnify l k1 k2


kfree (KVar v)                      = []
kfree (KFun ks k)                   = concatMap kfree (k:ks)
kfree _                             = []


----------------------------------------------------------------------------------------------------------------------
-- ksubst
----------------------------------------------------------------------------------------------------------------------

class KSubst s where
    ksubst                          :: Bool -> s -> KindM s             -- Bool flag controls whether free KVars are replaced with KType or not

instance KSubst a => KSubst [a] where
    ksubst g                        = mapM (ksubst g)

instance KSubst a => KSubst (Maybe a) where
    ksubst g                        = maybe (return Nothing) (\x -> Just <$> ksubst g x)

instance KSubst Kind where
    ksubst g KWild                  = return KWild
    ksubst g (KVar v)               = do s <- getSubstitution
                                         case Map.lookup v s of
                                            Just k  -> ksubst g k
                                            Nothing -> return (if g then KType else KVar v)
    ksubst g (KFun ks k)            = KFun <$> mapM (ksubst g) ks <*> ksubst g k
    ksubst g k                      = return k
        
instance KSubst TSchema where
    ksubst g (TSchema l q t)        = TSchema l <$> ksubst g q <*> ksubst g t

instance KSubst TVar where
    ksubst g (TV k n)               = TV <$> ksubst g k <*> return n
    
instance KSubst TCon where
    ksubst g (TC n ts)              = TC n <$> ksubst g ts

instance KSubst QBind where
    ksubst g (Quant v cs)           = Quant <$> ksubst g v <*> ksubst g cs

instance KSubst Type where
    ksubst g (TVar l v)             = TVar l <$> ksubst g v
    ksubst g (TCon l c)             = TCon l <$> ksubst g c
    ksubst g (TFun l fx p k t)      = TFun l <$> ksubst g fx <*> ksubst g p <*> ksubst g k<*> ksubst g t
    ksubst g (TTuple l p k)         = TTuple l <$> ksubst g p <*> ksubst g k
    ksubst g (TUnion l as)          = return $ TUnion l as
    ksubst g (TOpt l t)             = TOpt l <$> ksubst g t
    ksubst g (TNone l)              = return $ TNone l
    ksubst g (TNil l s)             = return $ TNil l s
    ksubst g (TRow l k n t r)       = TRow l k n <$> ksubst g t <*> ksubst g r
    ksubst g (TFX l fx)             = TFX l <$> ksubst g fx

instance KSubst FX where
    ksubst g FXPure                 = return FXPure
    ksubst g (FXMut t)              = FXMut <$> ksubst g t
    ksubst g (FXAct t)              = FXAct <$> ksubst g t
    ksubst g FXAction               = return FXAction

instance KSubst Stmt where
    ksubst g (Expr l e)             = Expr l <$> ksubst g e
    ksubst g (Assign l ps e)        = Assign l <$> ksubst g ps <*> ksubst g e
    ksubst g (MutAssign l t e)      = MutAssign l <$> ksubst g t <*> ksubst g e
    ksubst g (AugAssign l t op e)   = AugAssign l <$> ksubst g t <*> return op <*> ksubst g e
    ksubst g (Assert l e mbe)       = Assert l <$> ksubst g e <*> ksubst g mbe
    ksubst g (Pass l)               = return $ Pass l
    ksubst g (Delete l t)           = Delete l <$> ksubst g t
    ksubst g (Return l mbe)         = Return l <$> ksubst g mbe
    ksubst g (Raise l mbex)         = Raise l <$> ksubst g mbex
    ksubst g (Break l)              = return $ Break l
    ksubst g (Continue l)           = return $ Continue l
    ksubst g (If l bs els)          = If l <$> ksubst g bs <*> ksubst g els
    ksubst g (While l e b els)      = While l <$> ksubst g e <*> ksubst g b <*> ksubst g els
    ksubst g (For l p e b els)      = For l <$> ksubst g p <*> ksubst g e <*> ksubst g b <*> ksubst g els
    ksubst g (Try l b hs els fin)   = Try l <$> ksubst g b <*> ksubst g hs <*> ksubst g els <*> ksubst g fin
    ksubst g (With l is b)          = With l <$> ksubst g is <*> ksubst g b
    ksubst g (Data l mbt ss)        = Data l <$> ksubst g mbt <*> ksubst g ss
    ksubst g (VarAssign l ps e)     = VarAssign l <$> ksubst g ps <*> ksubst g e
    ksubst g (After l e e')         = After l <$> ksubst g e <*> ksubst g e'
    ksubst g (Decl l ds)            = Decl l <$> ksubst g ds
    ksubst g (Signature l ns t d)   = Signature l ns <$> ksubst g t <*> return d

instance KSubst Decl where
    ksubst g (Def l n q p k a b d x)= Def l n <$> ksubst g q <*> ksubst g p <*> ksubst g k <*> ksubst g a <*> ksubst g b <*> return d <*> ksubst g x
    ksubst g (Actor l n q p k b)    = Actor l n <$> ksubst g q <*> ksubst g p <*> ksubst g k <*> ksubst g b
    ksubst g (Class l n q as b)     = Class l n <$> ksubst g q <*> ksubst g as <*> ksubst g b
    ksubst g (Protocol l n q as b)  = Protocol l n <$> ksubst g q <*> ksubst g as <*> ksubst g b
    ksubst g (Extension l n q as b) = Extension l n <$> ksubst g q <*> ksubst g as <*> ksubst g b

instance KSubst Expr where
    ksubst g (Var l n)              = return $ Var l n
    ksubst g (Int l i s)            = return $ Int l i s
    ksubst g (Float l f s)          = return $ Float l f s
    ksubst g (Imaginary l i s)      = return $ Imaginary l i s
    ksubst g (Bool l b)             = return $ Bool l b
    ksubst g (None l)               = return $ None l
    ksubst g (NotImplemented l)     = return $ NotImplemented l
    ksubst g (Ellipsis l)           = return $ Ellipsis l
    ksubst g (Strings l ss)         = return $ Strings l ss
    ksubst g (BStrings l ss)        = return $ BStrings l ss
    ksubst g (Call l e ts ps ks)    = Call l <$> ksubst g e <*> ksubst g ts <*> ksubst g ps <*> ksubst g ks
    ksubst g (Index l e is)         = Index l <$> ksubst g e <*> ksubst g is
    ksubst g (Slice l e sl)         = Slice l <$> ksubst g e <*> ksubst g sl
    ksubst g (Cond l e1 e2 e3)      = Cond l <$> ksubst g e1 <*> ksubst g e2 <*> ksubst g e3
    ksubst g (BinOp l e1 op e2)     = BinOp l <$> ksubst g e1 <*> return op <*> ksubst g e2
    ksubst g (CompOp l e ops)       = CompOp l <$> ksubst g e <*> ksubst g ops
    ksubst g (UnOp l op e)          = UnOp l op <$> ksubst g e 
    ksubst g (Dot l e n)            = Dot l <$> ksubst g e <*> return n
    ksubst g (DotI l e i t)         = DotI l <$> ksubst g e <*> return i <*> return t
    ksubst g (Lambda l ps ks e fx)  = Lambda l <$> ksubst g ps <*> ksubst g ks <*> ksubst g e <*> ksubst g fx
    ksubst g (Yield l e)            = Yield l <$> ksubst g e
    ksubst g (YieldFrom l e)        = YieldFrom l <$> ksubst g e
    ksubst g (Tuple l es ks)        = Tuple l <$> ksubst g es <*> ksubst g ks
    ksubst g (List l es)            = List l <$> ksubst g es
    ksubst g (ListComp l e c)       = ListComp l <$> ksubst g e <*> ksubst g c
    ksubst g (Dict l as)            = Dict l <$> ksubst g as
    ksubst g (DictComp l a c)       = DictComp l <$> ksubst g a <*> ksubst g c
    ksubst g (Set l es)             = Set l <$> ksubst g es
    ksubst g (SetComp l e c)        = SetComp l <$> ksubst g e <*> ksubst g c
    ksubst g (Paren l e)            = Paren l <$> ksubst g e

instance KSubst Pattern where
    ksubst g (PVar l n a)           = PVar l n <$> ksubst g a
    ksubst g (PTuple l ps ks)       = PTuple l <$> ksubst g ps <*> ksubst g ks
    ksubst g (PList l ps p)         = PList l <$> ksubst g ps <*> ksubst g p
    ksubst g (PParen l p)           = PParen l <$> ksubst g p

instance KSubst Exception where
    ksubst g (Exception e mbe)      = Exception <$> ksubst g e <*> ksubst g mbe

instance KSubst Branch where
    ksubst g (Branch e ss)          = Branch <$> ksubst g e <*> ksubst g ss

instance KSubst Handler where
    ksubst g (Handler ex b)         = Handler ex <$> ksubst g b

instance KSubst PosPar where
    ksubst g (PosPar n t e p)       = PosPar n <$> ksubst g t <*> ksubst g e <*> ksubst g p
    ksubst g (PosSTAR n t)          = PosSTAR n <$> ksubst g t
    ksubst g PosNIL                 = return PosNIL
    
instance KSubst KwdPar where
    ksubst g (KwdPar n t e k)       = KwdPar n <$> ksubst g t <*> ksubst g e <*> ksubst g k
    ksubst g (KwdSTAR n t)          = KwdSTAR n <$> ksubst g t
    ksubst g KwdNIL                 = return KwdNIL
    
instance KSubst PosArg where
    ksubst g (PosArg e p)           = PosArg <$> ksubst g e <*> ksubst g p
    ksubst g (PosStar e)            = PosStar <$> ksubst g e
    ksubst g PosNil                 = return PosNil
    
instance KSubst KwdArg where
    ksubst g (KwdArg n e k)         = KwdArg n <$> ksubst g e <*> ksubst g k
    ksubst g (KwdStar e)            = KwdStar <$> ksubst g e
    ksubst g KwdNil                 = return KwdNil
    
instance KSubst PosPat where
    ksubst g (PosPat p ps)          = PosPat <$> ksubst g p <*> ksubst g ps
    ksubst g (PosPatStar p)         = PosPatStar <$> ksubst g p
    ksubst g PosPatNil              = return PosPatNil
    
instance KSubst KwdPat where
    ksubst g (KwdPat n p ps)        = KwdPat n <$> ksubst g p <*> ksubst g ps
    ksubst g (KwdPatStar p)         = KwdPatStar <$> ksubst g p
    ksubst g KwdPatNil              = return KwdPatNil
    
instance KSubst OpArg where
    ksubst g (OpArg op e)           = OpArg op <$> ksubst g e

instance KSubst Comp where
    ksubst g (CompFor l p e c)      = CompFor l <$> ksubst g p <*> ksubst g e <*> ksubst g c
    ksubst g (CompIf l e c)         = CompIf l <$> ksubst g e <*> ksubst g c
    ksubst g NoComp                 = return NoComp

instance KSubst WithItem where
    ksubst g (WithItem e p)         = WithItem <$> ksubst g e <*> ksubst g p

instance KSubst Elem where
    ksubst g (Elem e)               = Elem <$> ksubst g e
    ksubst g (Star e)               = Star <$> ksubst g e

instance KSubst Assoc where
    ksubst g (Assoc e1 e2)          = Assoc <$> ksubst g e1 <*> ksubst g e2
    ksubst g (StarStar e)           = StarStar <$> ksubst g e
  
instance KSubst Sliz where
    ksubst g (Sliz l e1 e2 e3)      = Sliz l <$> ksubst g e1 <*> ksubst g e2 <*> ksubst g e3


--------------------------------------------------------------------------------------------------------------

data KindError                      = KindError SrcLoc Kind Kind
                                    | InfiniteKind SrcLoc KVar Kind
                                    deriving (Show)

instance Control.Exception.Exception KindError

noUnify l k1 k2                     = Control.Exception.throw $ KindError l k1 k2
infiniteKind l v k                  = Control.Exception.throw $ InfiniteKind l v k

kindError (KindError l k1 k2)       = (l, " Expected a " ++ prstr k2 ++ ", actual kind is " ++ prstr k1)
kindError (InfiniteKind l v k)      = (l, " Infinite kind inferred: " ++ prstr  v ++ " = " ++ prstr k)
