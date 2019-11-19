{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}
module Acton.Types(reconstruct,solverError) where

import Debug.Trace
import Data.Typeable
import qualified Control.Exception
import System.FilePath.Posix (joinPath)
import System.Directory (doesFileExist)
import Control.Monad
--import Control.Monad.State
import Data.Maybe (maybeToList)
import Data.Graph (SCC(..), stronglyConnComp)
import Pretty
import Utils
import Acton.Syntax
import Acton.Names
import Acton.Builtin
import Acton.Env
import Acton.Solver
import qualified InterfaceFiles

reconstruct                             :: String -> Env -> Module -> IO (TEnv, Module, SrcInfo)
reconstruct outname env modul           = do InterfaceFiles.writeFile (outname ++ ".ty") (unalias env1 te)
                                             return (te, modul', info)
  where Module m imp suite              = modul
        env1                            = reserve (bound suite) env{ defaultmod = m }
        ((te,suite'),info)              = runTypeM $ (,) <$> infTop env1 suite <*> getDump
        modul'                          = Module m imp suite'

solverError                             = typeError

chkCycles (d@Class{} : ds)              = noforward (qual d) d ds && all (chkDecl d ds) (dbody d) && chkCycles ds
chkCycles (d@Protocol{} : ds)           = noforward (qual d) d ds && all (chkDecl d ds) (dbody d) && chkCycles ds
chkCycles (d : ds)                      = chkCycles ds
chkCycles []                            = True

chkDecl d ds s@Decl{}                   = chkCycles (decls s ++ ds)
chkDecl d ds s                          = noforward s d ds


noforward x d ds
  | not $ null vs                       = err2 vs "Illegal forward reference:"
  | otherwise                           = True
  where vs                              = free x `intersect` declnames (d:ds)

nodup x
  | not $ null vs                       = err2 vs "Duplicate names:"
  | otherwise                           = True
  where vs                              = duplicates (bound x)

noshadow svs x
  | not $ null vs                       = err2 vs "Illegal state shadowing:"
  | otherwise                           = True
  where vs                              = intersect (bound x) svs

noescape (te,e)                                                                               -- TODO: check for escaping classes/protocols as well
--  | not $ null dangling                 = err2 dangling "Dangling type signature for"       -- TODO: turn on again!
  | otherwise                           = (te,e)
  where dangling                        = dom (nSigs te) \\ dom (nVars te)


-- Infer -------------------------------

infTop                                  :: Env -> Suite -> TypeM (TEnv,Suite)
infTop env ss                           = do pushFX fxNil
                                             (te,ss') <- noescape <$> infEnv env ss
                                             popFX
                                             cs <- collectConstraints
                                             solve cs
                                             te' <- msubst te
                                             return (te', ss')

class Infer a where
    infer                               :: Env -> a -> TypeM (Type,a)

class InfEnv a where
    infEnv                              :: Env -> a -> TypeM (TEnv,a)

class InfEnvT a where
    infEnvT                             :: Env -> a -> TypeM (TEnv,Type,a)

class InfData a where
    infData                             :: Env -> a -> TypeM TEnv


splitGen                                :: Env -> [TVar] -> TEnv -> Constraints -> TypeM (Constraints, TEnv)
splitGen env tvs te cs
  | null ambig_cs                       = return (fixed_cs, mapVars generalize te)
  | otherwise                           = do solve ambig_cs
                                             cs1 <- simplify (fixed_cs++gen_cs)
                                             te1 <- msubst te
                                             tvs1 <- msubstTV tvs
                                             splitGen env tvs1 te1 cs1
  where 
    (fixed_cs, cs')                     = partition (null . (\\tvs) . tyfree) cs
    (ambig_cs, gen_cs)                  = partition (ambig te . tyfree) cs'
    ambig te vs                         = or [ not $ null (vs \\ tyfree info) | (n, info) <- te ]
    q_new                               = mkBinds gen_cs
    generalize (TSchema l q t dec)      = closeFX $ TSchema l (subst s (q_new++q)) (subst s t) dec
      where s                           = tybound q_new `zip` map tVar (tvarSupply \\ tvs \\ tybound q)

mkBinds cs                              = collect [] $ catMaybes $ map bound cs
  where
    bound (Sub env (TVar _ v) (TCon _ u))   = Just $ TBind v [u]                            -- TODO: capture env!!!!!!!!
    bound (Impl env (TVar _ v) u)           = Just $ TBind v [u]                            -- TODO: capture env!!!!!!!!
    bound c                             = trace ("### Unreduced constraint: " ++ prstr c) $ Nothing
    collect vs []                       = []
    collect vs (TBind v us : q)
      | v `elem` vs                     = collect vs q
      | otherwise                       = TBind v (us ++ concat [ us' | TBind v' us' <- q, v' == v ]) : collect (v:vs) q


genTEnv                                 :: Env -> TEnv -> TypeM TEnv
genTEnv env te                          = do cs <- collectConstraints
                                             cs1 <- simplify cs
                                             te1 <- msubst te
                                             tvs <- msubstTV (tyfree env)
                                             (cs2, te2) <- splitGen env tvs te1 cs1
                                             constrain cs2
                                             dump [ INS (loc v) t | (v, TSchema _ [] t _) <- nVars te1 ]
                                             dump [ GEN (loc v) t | (v, t) <- nVars te2 ]
                                             return te2

gen1                                    :: Env -> Name -> Type -> Decoration -> TypeM TSchema
gen1 env n t d                          = do te <- genTEnv env (nVar' n (monotype' t d))
                                             return $ snd $ head $ nVars te

commonTEnv                              :: Env -> [TEnv] -> TypeM TEnv
commonTEnv env []                       = return []
commonTEnv env tenvs                    = do unifyTEnv env tenvs vs
                                             return $ prune vs $ head tenvs
  where vs                              = foldr intersect [] $ map dom tenvs

unionTEnv                               :: Env -> [TEnv] -> TypeM TEnv
unionTEnv env tenvs                     = undefined                                 -- For data statements only. TODO: implement


infLiveEnv env x
  | fallsthru x                         = do (te,x') <- noescape <$> infEnv env x
                                             return (Just te, x')
  | otherwise                           = do (te,x') <- noescape <$> infEnv env x
                                             return (Nothing, x')

liveCombine te Nothing                  = te
liveCombine Nothing te'                 = te'
liveCombine (Just te) (Just te')        = Just $ nCombine te te'


instance (InfEnv a) => InfEnv [a] where
    infEnv env []                       = return ([], [])
    infEnv env (s : ss)                 = do (te1,s') <- infEnv env s
                                             (te2,ss') <- infEnv (define te1 env) ss
                                             return (nCombine te1 te2, s':ss')

instance InfEnv Stmt where
    infEnv env (Expr l e)               = do (_,e') <- infer env e
                                             return ([], Expr l e')
    infEnv env (Assign l pats e)
      | nodup pats                      = do (t1,e') <- infer env e
                                             (te,t2,pats') <- infEnvT env pats
                                             constrain [Sub env t1 t2]
                                             return (te, Assign l pats' e')
    infEnv env (AugAssign l pat o@(Op _ op) e)
                                        = do (t1,e') <- infer env e
                                             (t2,pat') <- infer env pat
                                             constrain [Sub env t1 t2, Impl env t2 (protocol op)]
                                             return ([], AugAssign l pat' o e')
      where protocol PlusA              = cPlus
            protocol MinusA             = cMinus
            protocol MultA              = cNumber
            protocol PowA               = cNumber
            protocol DivA               = cNumber
            protocol ModA               = cReal
            protocol EuDivA             = cReal
            protocol ShiftLA            = cIntegral
            protocol ShiftRA            = cIntegral
            protocol BOrA               = cLogical
            protocol BXorA              = cLogical
            protocol BAndA              = cLogical
            protocol MMultA             = cMatrix
    infEnv env (Assert l es)            = do es' <- mapM (inferBool env) es
                                             return ([], Assert l es')
    infEnv env s@(Pass l)               = return ([], s)
    infEnv env (Delete l pat)
      | nodup pat                       = do (_,pat') <- infer env pat                 -- TODO: constrain pat targets to opt type
                                             return ([], Delete l pat')
    infEnv env s@(Return l Nothing)     = do subFX env (fxRet tNone tWild)
                                             return ([], s)
    infEnv env (Return l (Just e))      = do (t,e') <- infer env e
                                             subFX env (fxRet t tWild)
                                             return ([], Return l (Just e'))
    infEnv env s@(Raise _ Nothing)      = return ([], s)
    infEnv env (Raise l (Just e))       = do (_,e') <- infer env e
                                             return ([], Raise l (Just e'))
    infEnv env s@(Break _)              = return ([], s)
    infEnv env s@(Continue _)           = return ([], s)
    infEnv env (If l bs els)            = do (tes,bs') <- fmap unzip $ mapM (infLiveEnv env) bs
                                             (te,els') <- infLiveEnv env els
                                             te1 <- commonTEnv env $ catMaybes (te:tes)
                                             return (te1, If l bs' els')
    infEnv env (While l e b els)        = do e' <- inferBool env e
                                             (_,b') <- noescape <$> infEnv env b
                                             (_,els') <- noescape <$> infEnv env els
                                             return ([], While l e' b' els')
    infEnv env (For l p e b els)
      | nodup p                         = do (te,t1,p') <- infEnvT env p
                                             (t2,e') <- infer env e
                                             (_,b') <- noescape <$> infEnv (define te env) b
                                             (_,els') <- noescape <$> infEnv env els
                                             constrain [Impl env t2 (cCollection t1)]
                                             return ([], For l p' e' b' els')
    infEnv env (Try l b hs els fin)     = do (te,b') <- infLiveEnv env b
                                             (te',els') <- infLiveEnv (maybe id define te $ env) els
                                             (tes,hs') <- fmap unzip $ mapM (infLiveEnv env) hs
                                             te1 <- commonTEnv env $ catMaybes $ (liveCombine te te'):tes
                                             (te2,fin') <- noescape <$> infEnv (define te1 env) fin
                                             return (nCombine te1 te2, Try l b' hs' els' fin')
    infEnv env (With l items b)
      | nodup items                     = do (te,items') <- infEnv env items
                                             (te1,b') <- noescape <$> infEnv (define te env) b
                                             return $ (prune (dom te) te1, With l items' b')

    infEnv env (VarAssign l pats e)
      | nodup pats                      = do (t1,e') <- infer env e
                                             (te,t2,pats') <- infEnvT env pats
                                             constrain [Sub env t1 t2]
                                             return (nState te, VarAssign l pats' e')
    
    infEnv env (Decl l ds)
      | nodup ds && noCheck env         = do (te1,ds1) <- infEnv env ds
                                             return (te1, Decl l ds1)
      | otherwise                       = do (te1,ds1) <- infEnv (setNoCheck env) ds
                                             ds2 <- check (define te1 env) ds1
                                             te2 <- genTEnv env te1
                                             return (te2, Decl l ds2)
            

    infEnv env (Data l _ _)             = notYet l "data syntax"
{-
    infEnv env (Data l Nothing b)       = do te <- infData env1 b
                                             let te1 = filter (notemp . fst) te1
                                             constrain [Equ (tRecord $ env2row tNil $ nVars te1) t]
                                             return []
      where t                           = undefined   -- WAS: getReturn env
            env1                        = reserve (filter istemp $ bound b) env

    infEnv env (Data l (Just p) b)
      | nodup p                         = do (te0, t) <- infEnvT env p
                                             (te1,te2) <- partition (istemp . fst) <$> infData env b
                                             constrain [Equ (tRecord $ env2row tNil $ nVars te2) t]
                                             return (nCombine te0 te1)

instance InfData [Stmt] where
    infData env []                      = return []
    infData env (s : ss)                = do te1 <- infData env s
                                             te2 <- infData (define (filter (istemp . fst) te1) env) ss
                                             unionTEnv env [te1,te2]

instance InfData Stmt where
    infData env (While _ e b els)       = do inferBool env e
                                             te1 <- infEnv env b
                                             te2 <- infEnv env els
                                             unionTEnv env [[], te1, te2]
    infData env (For _ p e b els)       = undefined
    infData env (If _ bs els)           = do tes <- mapM (infData env) bs
                                             te <- infData env els
                                             unionTEnv env (te:tes)
    infData env s                       = infEnv env s

instance InfData Branch where
    infData env (Branch e b)            = do inferBool env e
                                             infData env b
-}

instance InfEnv Decl where
    infEnv env d@(Actor _ n _ p k _ _)
      | not $ reserved n env            = illegalRedef n
      | nodup (p,k)                     = do d' <- instwild d
                                             sc <- instwild $ extractSchema env d'
                                             return (nVar' n sc, d')
    infEnv env d@(Def _ n _ p k _ _ _)
      | not $ reserved n env            = illegalRedef n
      | nodup (p,k)                     = do d' <- instwild d
                                             sc <- instwild $ extractSchema env d'
                                             return (nVar' n sc, d')
    infEnv env (Class l n q us b)
      | not $ reserved n env            = illegalRedef n
      | wf env q && wf env1 us          = do (te,b') <- noescape <$> infEnv env1 b
                                             return (nClass n q (mro env1 us1) te, Class l n q us1 b')
      where env1                        = reserve (bound b) $ defineSelf n q $ defineTVars q $ block (stateScope env) env
            us1                         = classBases env us
    infEnv env (Protocol l n q us b)
      | not $ reserved n env            = illegalRedef n
      | wf env q && wf env1 us          = do (te,b') <- infEnv env1 b
                                             return (nProto (defaultmod env) n q (mro env1 us1) te, Protocol l n q us1 b')
      where env1                        = reserve (bound b) $ defineSelf n q $ defineTVars q $ block (stateScope env) env  
            us1                         = protoBases env us
    infEnv env d@(Extension _ n q us b)
      | isProto env n                   = notYet (loc n) "Extension of a protocol"
      | wf env q && wf env1 us          = do w <- newName (noqual n)
                                             return (nExt w n q (mro env1 (protoBases env us)), d)
      where env1                        = reserve (bound b) $ defineSelf' n q $ defineTVars q $ block (stateScope env) env
            u                           = TC n [ tVar tv | TBind tv _ <- q ]
    infEnv env d@(Signature _ ns _)
      | not $ null redefs               = illegalRedef (head redefs)
      | otherwise                       = do sc <- instwild $ extractSchema env d
                                             return (nSig ns sc, d)
      where redefs                      = [ n | n <- ns, not $ reserved n env ]

classBases env []                       = []
classBases env (u:us)
  | isProto env (tcname u)              = u : protoBases env us
  | otherwise                           = u : protoBases env us

protoBases env []                       = []
protoBases env (u:us)
  | isProto env (tcname u)              = u : protoBases env us
  | otherwise                           = err1 u "Protocol expected"

mro env us                              = merge [] $ linearizations us ++ [us]
  where merge out lists
          | null heads                  = reverse out
          | h:_ <- good                 = merge (h:out) [ if match hd h then tl else hd:tl | (hd,tl) <- zip heads tails ]
          | otherwise                   = err2 heads "Inconsistent resolution order for"
          where (heads,tails)           = unzip [ (hd,tl) | hd:tl <- lists ]
                good                    = [ h | h <- heads, all (absent (tcname h)) tails]

        match u1 u2
          | u1 == u2                    = True
          | tcname u1 == tcname u2      = err2 [u1,u2] "Inconsistent instantiations of class/protocol"
          | otherwise                   = False

        absent n []                     = True
        absent n (u:us)
          | n == tcname u               = False
          | otherwise                   = absent n us

        linearizations []               = []
        linearizations (u : us)
          | all entail cs               = (u:us') : linearizations us
          | otherwise                   = err1 u ("Type context too weak to entail")
          where (cs, us', _)            = findCon env u


class Check a where
    check                               :: Env -> a -> TypeM a

instance (Check a) => Check [a] where
    check env ds                        = mapM (check env) ds

instance Check Stmt where
    check env (Decl l ds)               = Decl l <$> check env ds
    check env s                         = return s

instance Check Decl where
    check env (Actor l n q p k ann b)
      | noshadow svars (p,k)            = do pushFX (fxAct tWild)
                                             (te0,prow,p') <- infEnvT env p
                                             (te1,krow,k') <- infEnvT (define te0 env1) k
                                             (te2,b') <- noescape <$> infEnv (define te1 (define te0 env1)) b
                                             te3 <- genTEnv env te2
                                             fx <- fxAct <$> newTVar
                                             checkAssump env n (tFun fx prow krow (tRecord $ env2row tNil $ nVars te3))
                                             return $ Actor l n q p' k' ann b'
      where svars                       = statedefs b
            env0                        = define envActorSelf $ defineTVars q $ block (stateScope env) env
            env1                        = reserve (bound (p,k) ++ bound b ++ svars) env0
            
    check env (Def l n q p k ann b (Sync f))
      | noshadow svars (p,k)            = do t <- newTVar
                                             pushFX (fxRet t tWild)
                                             when (fallsthru b) (subFX env (fxRet tNone tWild))
                                             (te0,prow,p') <- infEnvT env p
                                             (te1,krow,k') <- infEnvT (define te0 env1) k
                                             (_,b') <- noescape <$> infEnv (define te1 (define te0 env1)) b
                                             popFX
                                             fx <- fxSync <$> newTVar
                                             checkAssump env n (tFun fx prow krow t)
                                             return $ Def l n q p' k' ann b' (Sync f)
      where svars                       = stateScope env
            env1                        = reserve (bound (p,k) ++ bound b \\ svars) $ defineTVars q env

    check env (Def l n q p k ann b Async)
      | noshadow svars (p,k)            = do t <- newTVar
                                             pushFX (fxRet t tWild)
                                             when (fallsthru b) (subFX env (fxRet tNone tWild))
                                             (te0,prow,p') <- infEnvT env p
                                             (te1,krow,k') <- infEnvT (define te0 env1) k
                                             (_,b') <- noescape <$> infEnv (define te1 (define te0 env1)) b
                                             popFX
                                             fx <- fxAsync <$> newTVar
                                             checkAssump env n (tFun fx prow krow (tMsg t))
                                             return $ Def l n q p' k' ann b' Async
      where svars                       = stateScope env
            env1                        = reserve (bound (p,k) ++ bound b \\ svars) $ defineTVars q env

    check env (Def l n q p k ann b modif)
                                        = do t <- newTVar
                                             fx <- newTVar
                                             pushFX (fxRet t fx)
                                             when (fallsthru b) (subFX env (fxRet tNone tWild))
                                             (te0,prow,p') <- infEnvT env p
                                             (te1,krow,k') <- infEnvT (define te0 env1) k
                                             (_,b') <- noescape <$> infEnv (define te1 (define te0 env1)) b
                                             popFX
                                             (prow',krow') <- splitRows modif prow krow
                                             checkAssump env n (tFun fx prow' krow' t)
                                             return $ Def l n q p' k' ann b' modif
      where env1                        = reserve (bound (p,k) ++ bound b) $ defineTVars q $ block (stateScope env) env
            splitRows m p@(TNil _) k    = (,) <$> return p <*> splitRow m k
            splitRows m p k             = (,) <$> splitRow m p <*> return k
            splitRow (InstMeth _) (TRow _ n sc r)
                                        = constrain [Equ env (monotypeOf sc) tSelf] >> return r
            splitRow (ClassMeth) (TRow _ n sc r)
                                        = constrain [Equ env (monotypeOf sc) (tAt (findSelf env))] >> return r
            splitRow m r                = return r

    check env (Class l n q us b)        = do pushFX fxNil
                                             b' <- check (define te env1) b
                                             popFX
                                             checkBindings env False us te
                                             return $ Class l n q us b'
      where env1                        = defineSelf n q $ defineTVars q $ block (stateScope env) env
            (q,us,te)                   = findClass (NoQual n) env

    check env (Protocol l n q us b)     = do pushFX fxNil
                                             b' <- check (define te env1) b
                                             popFX
                                             checkBindings env True us te
                                             return $ Protocol l n q us b'
      where env1                        = defineSelf n q $ defineTVars q $ block (stateScope env) env
            (q,us,te)                   = findProto (NoQual n) env

    check env (Extension l n q us b)    = do pushFX fxNil
                                             (te,b') <- infEnv env1 b
                                             popFX
                                             checkBindings env False us te
                                             return $ Extension l n q us b'
      where env1                        = reserve (bound b) $ defineSelf' n q $ defineTVars q $ block (stateScope env) env
    check env d@(Signature l ns sc)     = return d


checkBindings env proto us te
  | proto && (not $ null unsigs)        = lackSig unsigs
  | not proto && (not $ null undefs)    = lackDef undefs
  | otherwise                           = constrain refinements
  where tes                             = [ te' | u <- us, let (_,_,te') = findCon env u ]
        inherited                       = concatMap nSigs tes ++ concatMap nVars tes
        refinements                     = [ SubGen env sc sc' | (n,sc) <- nSigs te, Just sc' <- [lookup n inherited] ]
        undefs                          = (dom $ nSigs te ++ concatMap nSigs tes) \\ (dom $ nVars te ++ concatMap nVars tes)
        unsigs                          = dom te \\ (dom (nSigs te) ++ dom inherited)


checkAssump env n t                     = case findVarType n env of
                                            (TSchema _ [] t' _) -> 
                                               constrain [Equ env t t']
                                            sc -> do
                                               sc' <- gen1 env n t (scdec sc)   -- TODO: verify that generalizing one decl at a time is ok
                                               constrain [EquGen env sc' sc]

inferPure env e                         = do pushFX tNil
                                             t <- infer env e
                                             popFX
                                             return t

env2row                                 = foldl (\r (n,t) -> kwdRow n t r)           -- TODO: stabilize this...

instance InfEnv Branch where
    infEnv env (Branch e b)             = do e' <- inferBool env e
                                             (te,b') <- noescape <$> infEnv env b
                                             return (te, Branch e' b')

instance InfEnv WithItem where
    infEnv env (WithItem e Nothing)     = do (t,e') <- infer env e
                                             constrain [Impl env t cContextManager]
                                             return ([], WithItem e' Nothing)
    infEnv env (WithItem e (Just p))    = do (t1,e') <- infer env e
                                             (te,t2,p') <- infEnvT env p
                                             constrain [Equ env t1 t2, Impl env t1 cContextManager]
                                             return (te, WithItem e' (Just p'))

instance InfEnv Handler where
    infEnv env (Handler ex b)           = do (te,ex') <- infEnv env ex
                                             (te1,b') <- noescape <$> infEnv (define te env) b
                                             return (prune (dom te) te1, Handler ex' b')

instance InfEnv Except where
    infEnv env ex@(ExceptAll l)         = return ([], ex)
    infEnv env ex@(Except l x)          = do (cs,t) <- instantiate env $ classConSchema env x
                                             constrain (Sub env t tException : cs)
                                             return ([], ex)
    infEnv env ex@(ExceptAs l x n)      = do (cs,t) <- instantiate env $ classConSchema env x
                                             constrain (Sub env t tException : cs)
                                             return (nVar n t, ex)

classConSchema env qn                   = tSchema q (tCon $ TC qn $ map tVar $ tybound q)
  where (q,_,_)                         = findClass qn env

instance Infer Expr where
    infer env (Var l n)                 = do (cs,t) <- instantiate env $ openFX $ findVarType' n env
                                             constrain cs
                                             return (t, Var l n)
    infer env e@(Int _ val s)           = return (tInt, e)
    infer env e@(Float _ val s)         = return (tFloat, e)
    infer env e@Imaginary{}             = notYetExpr e
    infer env e@(Bool _ val)            = return (tBool, e)
    infer env e@(None _)                = return (tNone, e)
    infer env e@(NotImplemented _)      = notYetExpr e
    infer env e@(Ellipsis _)            = notYetExpr e
    infer env e@(Strings _ ss)          = return $ (tUnion [ULit $ concat ss], e)
    infer env e@(BStrings _ ss)         = return (tBytes, e)
    infer env (Call l e ps ks)          = do (t,e') <- infer env e
                                             dump [INS (loc e) t]
                                             (prow,ps') <- infer env ps
                                             (krow,ks') <- infer env ks
                                             t0 <- newTVar
                                             fx <- currFX
                                             constrain [Sub env t (tFun fx prow krow t0)]
                                             return (t0, Call l e' ps' ks')
    infer env (Await l e)               = do (t,e') <- infer env e
                                             t0 <- newTVar
                                             fx <- fxSync <$> newTVar
                                             equFX env fx
                                             constrain [Sub env t (tMsg t0)]
                                             return (t0, Await l e')
    infer env (Index l e [i])           = do (t,e') <- infer env e
                                             (ti,i') <- infer env i
                                             t0 <- newTVar
                                             constrain [Impl env t (cIndexed ti t0)]
                                             return (t0, Index l e' [i'])
    infer env (Slice l e [s])           = do (t,e') <- infer env e
                                             s' <- inferSlice env s
                                             constrain [Impl env t cSliceable]
                                             return (t, Slice l e' [s'])
    infer env (Cond l e1 e e2)          = do (t1,e1') <- infer env e1
                                             (t2,e2') <- infer env e2
                                             e' <- inferBool env e
                                             t0 <- newTVar
                                             constrain [Sub env t1 t0, Sub env t2 t0]
                                             return (t0, Cond l e1' e' e2')
    infer env (BinOp l e1 o@(Op _ op) e2)
      | op `elem` [Or,And]              = do (t1,e1') <- infer env e1
                                             (t2,e2') <- infer env e2
                                             constrain [Impl env t1 cBoolean, Impl env t2 cBoolean]
                                             return (tBool, BinOp l e1' o e2')
      | otherwise                       = do (t1,e1') <- infer env e1
                                             (t2,e2') <- infer env e2
                                             t <- newTVar
                                             constrain [Sub env t1 t, Sub env t2 t, Impl env t (protocol op)]
                                             return (t, BinOp l e1' o e2')
      where protocol Plus               = cPlus
            protocol Minus              = cMinus
            protocol Mult               = cNumber
            protocol Pow                = cNumber
            protocol Div                = cNumber
            protocol Mod                = cReal
            protocol EuDiv              = cReal
            protocol ShiftL             = cIntegral
            protocol ShiftR             = cIntegral
            protocol BOr                = cLogical
            protocol BXor               = cLogical
            protocol BAnd               = cLogical
            protocol MMult              = cMatrix
    infer env (UnOp l o@(Op _ op) e)
      | op == Not                       = do (t,e') <- infer env e
                                             constrain [Impl env t cBoolean]
                                             return (tBool, UnOp l o e')
      | otherwise                       = do (t,e') <- infer env e
                                             constrain [Impl env t (protocol op)]
                                             return (t, UnOp l o e')
      where protocol UPlus              = cNumber
            protocol UMinus             = cNumber
            protocol BNot               = cIntegral
    infer env (CompOp l e ops)          = do (t1,e') <- infer env e
                                             ops' <- walk t1 ops
                                             return (tBool, CompOp l e' ops')
      where walk t0 []                     = return []
            walk t0 (OpArg o@(Op l op) e:ops)
              | op `elem` [In,NotIn]    = do (t1,e') <- infer env e
                                             constrain [Impl env t1 (cCollection t0), Impl env t0 cEq]
                                             ops' <- walk t1 ops
                                             return (OpArg o e' : ops')
              | otherwise               = do (t1,e') <- infer env e
                                             t <- newTVar
                                             constrain [Sub env t0 t, Sub env t1 t, Impl env t (protocol op)]
                                             ops' <- walk t ops
                                             return (OpArg o e' : ops')
            protocol Eq                 = cEq
            protocol NEq                = cEq
            protocol LtGt               = cEq
            protocol Lt                 = cOrd
            protocol Gt                 = cOrd
            protocol LE                 = cOrd
            protocol GE                 = cOrd
            protocol Is                 = cIdentity
            protocol IsNot              = cIdentity
    infer env (Dot l e n)
      | Just m <- isModule env e        = infer env (Var l (QName m n))
      | otherwise                       = do (t,e') <- infer env e
                                             t0 <- newTVar
                                             constrain [Sel env t n t0]
                                             return (t0, Dot l e' n)
    infer env (DotI l e i)              = do (t,e') <- infer env e
                                             t0 <- newTVar
                                             constrain [Sel env t (rPos i) t0]
                                             return (t0, DotI l e' i)
    infer env (Lambda l p k e)
      | nodup (p,k)                     = do fx <- newTVar
                                             pushFX fx
                                             (te0, prow, p') <- infEnvT env1 p
                                             (te1, krow, k') <- infEnvT (define te0 env1) k
                                             (t,e') <- infer (define te1 (define te0 env1)) e
                                             popFX
                                             dump [INS l $ tFun fx prow krow t]
                                             return (tFun fx prow krow t, Lambda l p' k' e')
      where env1                        = reserve (bound (p,k)) env
    infer env e@Yield{}                 = notYetExpr e
    infer env e@YieldFrom{}             = notYetExpr e
    infer env (Tuple l pargs)           = do (prow,pargs') <- infer env pargs
                                             return (tTuple prow, Tuple l pargs')
    infer env (TupleComp l e co)
      | nodup co                        = do (te,co') <- infEnv env co
                                             (_,e') <- infer (define te env) e
                                             prow <- newTVar
                                             return (tTuple prow, TupleComp l e' co')       -- !! Extreme short-cut, for now
    infer env (Record l kargs)          = do (krow,kargs') <- infer env kargs
                                             return (tRecord krow, Record l kargs')
    infer env (RecordComp l n e co)
      | nodup co                        = do (te,co') <- infEnv env co
                                             let env1 = define te env
                                             _ <- infer env1 (Var (nloc n) (NoQual n))
                                             (_,e') <- infer env1 e
                                             krow <- newTVar
                                             return (tRecord krow, RecordComp l n e' co')   -- !! Extreme short-cut, for now
    infer env (List l es)               = do t0 <- newTVar
                                             es' <- infElems env es pSequence t0
                                             return (pSequence t0, List l es')
    infer env (ListComp l e1 co)
      | nodup co                        = do (te,co') <- infEnv env co
                                             t0 <- newTVar
                                             [e1'] <- infElems (define te env) [e1] pSequence t0
                                             return (pSequence t0, ListComp l e1' co')
    infer env (Set l es)                = do t0 <- newTVar
                                             es'  <- infElems env es pSet t0
                                             return (pSet t0, Set l es')
    infer env (SetComp l e1 co)
      | nodup co                        = do (te,co') <- infEnv env co
                                             t0 <- newTVar
                                             [e1'] <- infElems (define te env) [e1] pSet t0
                                             return (pSet t0, SetComp l e1' co')
                                             
    infer env (Dict l as)               = do tk <- newTVar
                                             tv <- newTVar
                                             as' <- infAssocs env as tk tv
                                             return (pMapping tk tv, Dict l as')
    infer env (DictComp l a1 co)
      | nodup co                        = do (te,co') <- infEnv env co
                                             tk <- newTVar
                                             tv <- newTVar
                                             [a1'] <- infAssocs (define te env) [a1] tk tv
                                             return (pMapping tk tv, DictComp l a1' co')
    infer env (Paren l e)               = do (t,e') <- infer env e
                                             return (t, Paren l e')


isModule env e                          = fmap ModName $ mfilter (isMod env) $ fmap reverse $ dotChain e
  where dotChain (Var _ (NoQual n))     = Just [n]
        dotChain (Dot _ e n)            = fmap (n:) (dotChain e)
        dotChain _                      = Nothing


infElems env [] tc t0                   = return []
infElems env (Elem e : es) tc t0        = do (t,e') <- infer env e
                                             constrain [Sub env t t0]
                                             es' <- infElems env es tc t0
                                             return (Elem e' : es')
infElems env (Star e : es) tc t0        = do (t,e') <- infer env e
                                             constrain [Sub env t (tc t0)]
                                             es' <- infElems env es tc t0
                                             return (Star e' : es')

infAssocs env [] tk tv                  = return []
infAssocs env (Assoc k v : as) tk tv    = do (tk',k') <- infer env k
                                             (tv',v') <- infer env v
                                             constrain [Sub env tk' tk, Sub env tv' tv]
                                             as' <- infAssocs env as tv tk
                                             return (Assoc k' v' : as')
infAssocs env (StarStar e : as) tk tv   = do (t,e') <- infer env e
                                             constrain [Sub env t (pMapping tk tv)]
                                             as' <- infAssocs env as tk tv
                                             return (StarStar e' : as')

inferBool env e                         = do (t,e') <- infer env e
                                             constrain [Impl env t cBoolean]
                                             return e'

inferSlice env (Sliz l e1 e2 e3)        = do (t1,e1') <- infer env e1
                                             (t2,e2') <- infer env e2
                                             (t3,e3') <- infer env e3
                                             constrain [ Equ env t tInt | t <- [t1,t2,t3] ]
                                             return (Sliz l e1' e2' e3')
  where es                              = concat $ map maybeToList (e1:e1:maybeToList e3)

inferGen env e                          = do (t,e') <- infer env e
                                             sc <- gen1 env (name "_") t NoDec
                                             return (sc,e')

instance (Infer a) => Infer (Maybe a) where
    infer env Nothing                   = do t <- newTVar
                                             return (t, Nothing)
    infer env (Just x)                  = do (t,e') <- infer env x
                                             return (t, Just e')

instance InfEnvT PosPar where
    infEnvT env (PosPar n ann e p)      = do t <- maybeInstSC ann
                                             (t',e') <- inferGen env e
                                             constrain [SubGen env t' t]
                                             (te,r,p') <- infEnvT (define (nVar' n t) env) p
                                             return (nVar' n t ++ te, posRow t r, PosPar n (Just t) e' p')
    infEnvT env (PosSTAR n ann)         = do t <- maybeInstT ann
                                             r <- newTVar
                                             constrain [Equ env t (tTuple r)]
                                             return (nVar n t, r, PosSTAR n (Just t))
    infEnvT env PosNIL                  = return ([], posNil, PosNIL)

instance InfEnvT KwdPar where
    infEnvT env (KwdPar n ann e k)      = do t <- maybeInstSC ann
                                             (t',e') <- inferGen env e
                                             constrain [SubGen env t' t]
                                             (te,r,k') <- infEnvT (define (nVar' n t) env) k
                                             return (nVar' n t ++ te, kwdRow n t r, KwdPar n (Just t) e' k')
    infEnvT env (KwdSTAR n ann)         = do t <- maybeInstT ann
                                             r <- newTVar
                                             constrain [Equ env t (tRecord r)]
                                             return (nVar n t, r, KwdSTAR n (Just t))
    infEnvT env KwdNIL                  = return ([], kwdNil, KwdNIL)

instance Infer PosArg where
    infer env (PosArg e p)              = do (sc,e') <- inferGen env e
                                             (prow,p') <- infer env p
                                             return (posRow sc prow, PosArg e' p')
    infer env (PosStar e)               = do (t,e') <- infer env e
                                             prow <- newTVar
                                             constrain [Equ env t (tTuple prow)]
                                             return (prow, PosStar e')
    infer env PosNil                    = return (posNil, PosNil)
    
instance Infer KwdArg where
    infer env (KwdArg n e k)            = do (sc,e') <- inferGen env e
                                             (krow,k') <- infer env k
                                             return (kwdRow n sc krow, KwdArg n e' k')
    infer env (KwdStar e)               = do (t,e') <- infer env e
                                             krow <- newTVar
                                             constrain [Equ env t (tRecord krow)]
                                             return (krow, KwdStar e')
    infer env KwdNil                    = return (kwdNil, KwdNil)
    
instance InfEnv Comp where
    infEnv env NoComp                   = return ([], NoComp)
    infEnv env (CompIf l e c)           = do e' <- inferBool env e
                                             (te,c') <- infEnv env c
                                             return (te, CompIf l e' c')
    infEnv env (CompFor l p e c)        = do (te1,t1,p') <- infEnvT env p
                                             (t2,e') <- infer env e
                                             (te2,c') <- infEnv (define te1 env) c
                                             constrain [Impl env t2 (cCollection t1)]
                                             return (nCombine te1 te2, CompFor l p' e' c')

instance Infer Exception where
    infer env (Exception e1 Nothing)    = do (t1,e1') <- infer env e1
                                             constrain [Sub env t1 tException]
                                             return (t1, Exception e1' Nothing)
    infer env (Exception e1 (Just e2))  = do (t1,e1') <- infer env e1
                                             constrain [Sub env t1 tException]
                                             (t2,e2') <- infer env e2
                                             constrain [Sub env t2 (tOpt tException)]
                                             return (t1, Exception e1' (Just e2'))

instance InfEnvT [Pattern] where
    infEnvT env []                      = do t <- newTVar
                                             return ([], t, [])
    infEnvT env (p:ps)                  = do (te1,t1,p') <- infEnvT env p
                                             (te2,t2,ps') <- infEnvT (define te1 env) ps
                                             constrain [Equ env t1 t2]
                                             return (nCombine te1 te2, t1, p':ps')

instance InfEnvT (Maybe Pattern) where
    infEnvT env Nothing                 = do t <- newTVar
                                             return ([], pSequence t, Nothing)
    infEnvT env (Just p)                = do (te,t,p') <- infEnvT env p
                                             return (te, pSequence t, Just p')

instance InfEnvT PosPat where
    infEnvT env (PosPat p ps)           = do (te1,t,p') <- infEnvT env p
                                             (te2,r,ps') <- infEnvT (define te1 env) ps
                                             return (nCombine te1 te2, posRow (monotype t) r, PosPat p' ps')
    infEnvT env (PosPatStar p)          = do (te,t,p') <- infEnvT env p
                                             r <- newTVar
                                             constrain [Equ env t (tTuple r)]
                                             return (te, r, PosPatStar p')
    infEnvT env PosPatNil               = return ([], posNil, PosPatNil)


instance InfEnvT KwdPat where
    infEnvT env (KwdPat n p ps)         = do (te1,t,p') <- infEnvT env p
                                             (te2,r,ps') <- infEnvT (define te1 env) ps
                                             return (nCombine te1 te2, kwdRow n (monotype t) r, KwdPat n p' ps')
    infEnvT env (KwdPatStar p)          = do (te,t,p') <- infEnvT env p
                                             r <- newTVar
                                             constrain [Equ env t (tRecord r)]
                                             return (te, r, KwdPatStar p')
    infEnvT env KwdPatNil               = return ([], kwdNil, KwdPatNil)


instance InfEnvT Pattern where
    infEnvT env (PVar l n ann)
      | wfWild env ann                  = do case reservedOrSig n env of
                                                 Just Nothing -> do
                                                     t0 <- maybeInstT ann
                                                     return (nVar n t0, t0, PVar l n (Just t0))
                                                 Just (Just (TSchema _ [] t1 _)) -> do
                                                     t0 <- maybeInstT ann
                                                     constrain [Equ env t0 t1]
                                                     return (nVar n t1, t0, PVar l n (Just t0)) -- TODO: return scheme t1 instead
                                                 Just (Just sc) ->
                                                     err1 sc "Polymorphic annotation on assignment variable"
                                                 Nothing 
                                                   | ann == Nothing ->
                                                       case findVarType n env of
                                                         TSchema _ [] t _ -> return ([], t, PVar l n Nothing)
                                                         _ -> err1 n "Polymorphic variable not assignable:"
                                                   | otherwise ->
                                                       err1 ann "Type annotation on reassignment"
    infEnvT env (PIndex l e [i])        = do (t,e') <- infer env e
                                             (ti,i') <- infer env i
                                             t0 <- newTVar
                                             constrain [Impl env t (cIndexed ti t0)]    -- TODO: ensure MutableIndexed
                                             equFX env (fxMut tWild)
                                             return ([], t0, PIndex l e' [i'])
    infEnvT env (PSlice l e [s])        = do (t,e') <- infer env e
                                             s' <- inferSlice env s
                                             constrain [Impl env t cSliceable]          -- TODO: ensure MutableSliceable
                                             equFX env (fxMut tWild)
                                             return ([], t, PSlice l e' [s'])
    infEnvT env (PDot l e n)            = do (t,e') <- infer env e
                                             t0 <- newTVar
                                             constrain [Mut env t n t0]
                                             equFX env (fxMut tWild)
                                             return ([], t0, PDot l e' n)
    infEnvT env (PTuple l ps)           = do (te,prow,ps') <- infEnvT env ps
                                             return (te, tTuple prow, PTuple l ps')
--    infEnvT env (PRecord _ ps)          = do (te, krow) <- infEnvT env ps
--                                             return (te, tRecord krow)
    infEnvT env (PList l ps p)          = do (te1,t1,ps') <- infEnvT env ps
                                             (te2,t2,p') <- infEnvT (define te1 env) p
                                             constrain [Equ env (pSequence t1) t2]
                                             return (nCombine te1 te2, t2, PList l ps' p')
    infEnvT env (PParen l p)            = do (te,t,p') <- infEnvT env p
                                             return (te, t, PParen l p')
    infEnvT env (PData l n es)          = do t0 <- newTVar
                                             (t,es') <- inferIxs env t0 es
                                             return (nVar n t0, t, PData l n es')

inferIxs env t0 []                      = return (t0, [])
inferIxs env t0 (i:is)                  = do t1 <- newTVar
                                             (ti,i') <- infer env i
                                             constrain [Impl env t0 (cIndexed ti t1)]
                                             (t, is') <- inferIxs env t1 is
                                             return (t, i':is')

instance Infer Pattern where
    infer env p                         = noenv <$> infEnvT env p
      where noenv ([],t,e)              = (t,e)
            noenv (te,_,_)              = nameNotFound (head (dom te))
                                             

-- Well-formed types ------------------------------------------------------

wf env t                            = wfmd env False t

wfWild env t                        = wfmd env True t

instWF env Nothing                  = newTVar
instWF env (Just t)
  | wfWild env t                    = instwild t

class WellFormed a where
    wfmd                            :: Env -> Bool -> a -> Bool

instance (WellFormed a) => WellFormed (Maybe a) where
    wfmd env w                      = maybe True (wfmd env w)

instance WellFormed [TBind] where
    wfmd env w []                   = True
    wfmd env w (b:bs)               = wfmd env w b && wfmd env1 w bs
      where env1                    = defineTVars [b] env

instance WellFormed [TCon] where
    wfmd env w cs                   = all (wfmd env w) cs

instance WellFormed TSchema where
    wfmd env w (TSchema l [] t d)   = wfmd env1 w t
      where q                       = [ TBind tv [] | tv <- tyfree t \\ tvarScope env ]
            env1                    = defineTVars q env
    wfmd env w (TSchema l q t d)    = wfmd env False q && wfmd env1 w t
      where env1                    = defineTVars q env

instance WellFormed TBind where
    wfmd env w (TBind tv us)        = all (wfmd env w) us

instance WellFormed TCon where
    wfmd env w (TC c ts)            = all (wfmd env w) ts

instance WellFormed Type where
    wfmd env False (TWild l)        = err1 l "Illegal wildcard type"
    wfmd env w (TVar _ tv)
      | tv `notElem` tvarScope env  = err1 tv "Unbound type variable"
    wfmd env w (TCon _ tc)          = wfmd env w tc
    wfmd env w (TAt _ tc)           = wfmd env w tc
    wfmd env w (TFun _ e p k t)     = wfmd env w e && wfmd env w p && wfmd env w k && wfmd env w t
    wfmd env w (TTuple _ p)         = wfmd env w p
    wfmd env w (TRecord _ k)        = wfmd env w k
    wfmd env w (TOpt _ t)           = wfmd env w t
    wfmd env w (TRow _ n t r)       = wfmd env w t && wfmd env w r
    wfmd env w t                    = True

class Wild a where
    instwild                        :: a -> TypeM a

instance Wild [TBind] where
    instwild                        = mapM instwild

instance Wild [TCon] where
    instwild                        = mapM instwild

instance Wild TSchema where
    instwild (TSchema l q t d)      = TSchema l q <$> instwild t <*> return d

instance Wild TBind where
    instwild (TBind tv us)          = TBind tv <$> mapM instwild us

instance Wild TCon where
    instwild (TC c ts)              = TC c <$> mapM instwild ts

instance Wild Type where
    instwild (TWild _)              = newTVar
    instwild (TCon l tc)            = TCon l <$> instwild tc
    instwild (TAt l tc)             = TAt l <$> instwild tc
    instwild (TFun l e p k t)       = TFun l <$> instwild e <*> instwild p <*> instwild k <*> instwild t
    instwild (TTuple l p)           = TTuple l <$> instwild p
    instwild (TRecord l k)          = TRecord l <$> instwild k
    instwild (TOpt l t)             = TOpt l <$> instwild t
    instwild (TRow l n t r)         = TRow l n <$> instwild t <*> instwild r
    instwild t                      = return t

instance Wild Decl where
    instwild (Def l n q p k t b m)  = Def l n q <$> instwild p <*> instwild k <*> justInstT t <*> return b <*> return m
    instwild (Actor l n q p k t b)  = Actor l n q <$> instwild p <*> instwild k <*> justInstT t <*> return b
    instwild d                      = return d

instance (Wild a) => Wild (Maybe a) where
    instwild Nothing                = return Nothing
    instwild (Just t)               = Just <$> instwild t

instance Wild PosPar where
    instwild (PosPar n t e p)       = PosPar n <$> justInstSC t <*> return e <*> instwild p
    instwild (PosSTAR n t)          = PosSTAR n <$> justInstT t
    instwild PosNIL                 = return PosNIL

instance Wild KwdPar where
    instwild (KwdPar n t e p)       = KwdPar n <$> justInstSC t <*> return e <*> instwild p
    instwild (KwdSTAR n t)          = KwdSTAR n <$> justInstT t
    instwild KwdNIL                 = return KwdNIL

maybeInstT ann                      = maybe newTVar instwild ann
maybeInstSC ann                     = maybe (monotype <$> newTVar) instwild ann

justInstT ann                       = Just <$> maybeInstT ann
justInstSC ann                      = Just <$> maybeInstSC ann

class ExtractT a where
    extractT                        :: a -> Type

instance ExtractT PosPar where
    extractT (PosPar n t _ p)       = posRow (maybe (monotype tWild) id t) (extractT p)
    extractT (PosSTAR n t)          = posVar Nothing        -- safe to ignore type (not schema) annotation t here
    extractT PosNIL                 = posNil

instance ExtractT KwdPar where
    extractT (KwdPar n t _ k)       = kwdRow n (maybe (monotype tWild) id t) (extractT k)
    extractT (KwdSTAR n t)          = kwdVar Nothing        -- safe to ignore type (not schema) annotation t here
    extractT KwdNIL                 = kwdNil

instance ExtractT Modif where
    extractT (Sync _)               = fxSync fxNil
    extractT Async                  = fxAsync fxNil
    extractT _                      = tWild

instance ExtractT Decl where
    extractT d@Def{}                = tFun (extractT $ modif d) prow krow (maybe tWild id (ann d))
      where 
        (prow,krow)                 = chop (modif d) (extractT $ pos d) (extractT $ kwd d)
        chop ClassMeth p k          = chop1 p k
        chop (InstMeth _) p k       = chop1 p k
        chop _ p k                  = (p, k)
        chop1 (TRow _ n t p) k      = (p, k)
        chop1 TVar{} k              = missingSelf (dname d)
        chop1 p (TRow _ n t k)      = (p, k)
        chop1 _ _                   = missingSelf (dname d)
    extractT d@Actor{}              = tFun (fxAct fxNil) prow krow (maybe tWild id (ann d))
      where (prow,krow)             = (extractT $ pos d, extractT $ kwd d)
    extractT _                      = tWild

extractSchema env d@Signature{}     = dtyp d
extractSchema env d
  | wfWild env schema               = schema
  where
    schema                          = tSchema' q sig (deco d)
    sig                             = extractT d
    q | null (qual d)               = [ TBind v [] | v <- tyfree sig \\ tvarScope env, skolem v ]
      | otherwise                   = qual d
    deco Def{modif=StaticMeth}      = StaticMethod
    deco Def{modif=ClassMeth}       = ClassMethod
    deco Def{modif=InstMeth f}      = InstMethod f
    deco _                          = NoDec


-- FX presentation ---------------------

openFX (TSchema l q (TFun l' fx p r t) dec)
  | Just fx1 <- open fx             = TSchema l (TBind v [] : q) (TFun l' fx1 p r t) dec
  where open (TRow l n t fx)        = TRow l n t <$> open fx
        open (TNil l)               = Just (TVar l v)
        open (TVar _ _)             = Nothing
        v                           = head (tvarSupply \\ tybound q)
openFX t                            = t

closeFX (TSchema l q f@(TFun l' fx p r t) dec)
  | TVar _ v <- rowTail fx, sole v  = TSchema l (filter ((v`notElem`) . tybound) q) (TFun l' (subst [(v,tNil)] fx) p r t) dec
  where sole v                      = v `elem` tybound q && length (filter (==v) (tyfree q ++ tyfree f)) == 1
closeFX t                           = t
