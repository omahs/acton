module Acton.TypeM where

import Control.Monad.State.Strict
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

import Acton.Syntax
import Acton.Printer
import Utils

-- Type inference monad ------------------------------------------------------------------

type TVarMap                            = Map TVar Type

data TypeState                          = TypeState {
                                                nextint         :: Int,
                                                effectstack     :: [(TFX,Type)],
                                                deferred        :: Constraints,
                                                currsubst       :: TVarMap
                                          }

initTypeState s                         = TypeState { nextint = 1, effectstack = [], deferred = [], currsubst = s }

type TypeM a                            = State TypeState a

runTypeM                                :: TypeM a -> a
runTypeM m                              = evalState m (initTypeState Map.empty)
{-
type TypeM a                            = ExceptT TypeError (State TypeState) a

runTypeM                                :: TypeM a -> a
runTypeM m                              = case evalState (runExceptT m) (initTypeState Map.empty) of
                                            Right x -> x
                                            Left err -> internal ("Unhandled TypeM error: " ++ show err)
-}
newUnique                               :: TypeM Int
newUnique                               = state $ \st -> (nextint st, st{ nextint = nextint st + 1 })

pushFX                                  :: TFX -> Type -> TypeM ()
pushFX fx ret                           = state $ \st -> ((), st{ effectstack = (fx,ret) : effectstack st })

currFX                                  :: TypeM TFX
currFX                                  = state $ \st -> (fst $ head $ effectstack st, st)

currRet                                 :: TypeM Type
currRet                                 = state $ \st -> (snd $ head $ effectstack st, st)

popFX                                   :: TypeM ()
popFX                                   = state $ \st -> ((), st{ effectstack = tail (effectstack st) })

defer                                   :: Constraints -> TypeM ()
defer cs                                = state $ \st -> ((), st{ deferred = cs ++ deferred st })

collectDeferred                         :: TypeM Constraints
collectDeferred                         = state $ \st -> (deferred st, st{ deferred = [] })

substitute                              :: TVar -> Type -> TypeM ()
substitute tv t                         = trace ("  #substitute " ++ prstr tv ++ " ~ " ++ prstr t) $ 
                                          state $ \st -> ((), st{ currsubst = Map.insert tv t (currsubst st)})

getSubstitution                         :: TypeM (Map TVar Type)
getSubstitution                         = state $ \st -> (currsubst st, st)

setSubstitution                         :: Map TVar Type -> TypeM ()
setSubstitution s                       = state $ \st -> ((), st{ currsubst = s })

