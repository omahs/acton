module Main where

import qualified Acton.Parser
import qualified Acton.Syntax as A

import qualified Acton.Relabel
import qualified Acton.Env
import qualified Acton.QuickType
import qualified Acton.Kinds
import qualified Acton.Types
import qualified Acton.Solver
import qualified Acton.Normalizer
import qualified Acton.CPS
import qualified Acton.Deactorizer
import qualified Acton.LambdaLifter
import qualified Acton.CodeGen
{-
import qualified Yang.Syntax as Y
import qualified Yang.Parser
import qualified YangCompiler
-}
import Utils
import qualified Pretty
import qualified InterfaceFiles

import Control.Exception (throw,catch,displayException,IOException,ErrorCall)
import Control.Monad
import Options.Applicative
import Data.Monoid ((<>))
import Data.Graph
import qualified Data.List
import System.IO
import System.Directory
import System.Process
import System.FilePath.Posix
import qualified System.Environment
import qualified System.Exit

data Args       = Args {
                    parse   :: Bool,
                    kinds   :: Bool,
                    types   :: Bool,
                    sigs    :: Bool,
                    norm    :: Bool,
                    deact   :: Bool,
                    cps     :: Bool,
                    llift   :: Bool,
                    hgen    :: Bool,
                    cgen    :: Bool,
                    verbose :: Bool,
                    nobuiltin :: Bool,
                    syspath :: String,
                    root    :: String,
                    file    :: String
                }
                deriving Show

getArgs         = Args
                    <$> switch (long "parse"   <> help "Show the result of parsing")
                    <*> switch (long "kinds"   <> help "Show all the result after kind-checking")
                    <*> switch (long "types"   <> help "Show all inferred expression types")
                    <*> switch (long "sigs"    <> help "Show the inferred type signatures")
                    <*> switch (long "norm"    <> help "Show the result after syntactic normalization")
                    <*> switch (long "deact"   <> help "Show the result after deactorization")
                    <*> switch (long "cps"     <> help "Show the result after CPS conversion")
                    <*> switch (long "llift"   <> help "Show the result of lambda-lifting")
                    <*> switch (long "hgen"    <> help "Show the generated .h file")
                    <*> switch (long "cgen"    <> help "Show the generated .c file")
                    <*> switch (long "verbose" <> help "Print progress info during execution")
                    <*> switch (long "nobuiltin" <> help "No builtin module (only for compiling __builtin__.act)")
                    <*> strOption (long "path" <> metavar "TARGETDIR" <> value "" <> showDefault)
                    <*> strOption (long "root" <> value "" <> showDefault)
                    <*> argument str (metavar "FILE")

descr           = fullDesc <> progDesc "Compile an Acton source file with necessary recompilation of imported modules"
                    <> header "actonc - the Acton compiler"

main            = do args <- execParser (info (getArgs <**> helper) descr)
                     paths <- findPaths args
                     when (verbose args) $ do
                         putStrLn ("## sysPath: " ++ sysPath paths)
                         putStrLn ("## sysRoot: " ++ sysRoot paths)
                         putStrLn ("## srcRoot: " ++ srcRoot paths)
                         putStrLn ("## modPrefix: " ++ prstrs (modPrefix paths))
                         putStrLn ("## topMod: " ++ prstr (topMod paths))
                     let mn = topMod paths
                     (case ext paths of
                        ".act"   -> do (src,tree) <- Acton.Parser.parseModule mn (file args)
                                                        `catch` handle Acton.Parser.parserError "" paths mn
                                       iff (parse args) $ dump "parse" (Pretty.print tree)
                                       let task = ActonTask mn src tree
                                       chaseImportsAndCompile args paths task
                        ".ty"    -> showTyFile args
                        _        -> error ("********************\nUnknown file extension "++ ext paths))
                               `catch` handle (\exc -> (l0,displayException (exc :: IOException))) "" paths mn
                               `catch` handle (\exc -> (l0,displayException (exc :: ErrorCall))) "" paths mn
  where showTyFile args     = do te <- InterfaceFiles.readFile (file args)
                                 putStrLn ("**** Type environment in " ++ (file args) ++ " ****")
                                 putStrLn (Pretty.render (Pretty.pretty (te :: Acton.Env.TEnv)))


iff True m      = m >> return ()
iff False _     = return ()

dump h txt      = putStrLn ("\n\n#################################### " ++ h ++ ":\n" ++ txt)

data Paths      = Paths {
                    sysPath     :: FilePath,
                    sysRoot     :: FilePath,
                    srcRoot     :: FilePath,
                    modPrefix   :: [String],
                    ext         :: String,
                    topMod      :: A.ModName
                  }

-- Given a FILE and optionally --path PATH:
-- 'sysPath' is the path to the system directory as given by PATH, defaulting to the actonc executable directory.
-- 'sysRoot' is the root of the system's private module tree (directory "modules" under 'sysPath').
-- 'srcRoot' is the root of a user's source tree (the longest directory prefix of FILE containing an ".acton" file)
-- 'modPrefix' is the module prefix of the source tree under 'srcRoot' (the directory name at 'srcRoot' split at every '.')
-- 'ext' is file suffix of FILE.
-- 'topMod' is the module name of FILE (its path after 'srcRoot' except 'ext', split at every '/')

srcFile                 :: Paths -> A.ModName -> Maybe FilePath
srcFile paths mn        = case stripPrefix (modPrefix paths) (A.modPath mn) of
                            Just ns -> Just $ joinPath (srcRoot paths : ns) ++ ".act"
                            Nothing -> Nothing

sysFile                 :: Paths -> A.ModName -> FilePath
sysFile paths mn        = joinPath (sysRoot paths : A.modPath mn)


touchDirs               :: FilePath -> A.ModName -> IO ()
touchDirs path mn       = touch path (init $ A.modPath mn)
  where 
    touch path []       = return ()
    touch path (d:dirs) = do found <- doesDirectoryExist path1
                             if found then touch path1 dirs
                              else do createDirectory path1
                                      touch path1 dirs
      where path1       = joinPath [path,d]

findPaths               :: Args -> IO Paths
findPaths args          = do execDir <- takeDirectory <$> System.Environment.getExecutablePath
                             sysPath <- canonicalizePath (if null $ syspath args then execDir else syspath args)
                             let sysRoot = joinPath [sysPath,"modules"]
                             absfile <- canonicalizePath (file args)
                             (srcRoot,subdirs) <- analyze (takeDirectory absfile) []
                             let modPrefix = if nobuiltin args || srcRoot == sysRoot then [] else split (takeFileName srcRoot)
                                 topMod = A.modName $ modPrefix++subdirs++[body]
                             touchDirs sysRoot topMod
                             return $ Paths sysPath sysRoot srcRoot modPrefix ext topMod
  where (body,ext)      = splitExtension $ takeFileName $ file args

        split           = foldr f [[]] where f c l@(x:xs) = if c == '.' then []:l else (c:x):xs

        analyze "/" ds  = error "********************\nNo .acton file found in any ancestor directory"
        analyze pre ds  = do exists <- doesFileExist (joinPath [pre, ".acton"])
                             if exists then return $ (pre, ds)
                              else analyze (takeDirectory pre) (takeFileName pre : ds)

data CompileTask        = ActonTask  {name :: A.ModName, src :: String, atree:: A.Module} deriving (Show)

importsOf :: CompileTask -> [A.ModName]
importsOf t = A.importsOf (atree t)

chaseImportsAndCompile :: Args -> Paths -> CompileTask -> IO ()
chaseImportsAndCompile args paths task
                       = do tasks <- chaseImportedFiles args paths (importsOf task) task
                            let sccs = stronglyConnComp  [(t,name t,importsOf t) | t <- tasks]
                                (as,cs) = Data.List.partition isAcyclic sccs
                            if null cs
                             then do env0 <- Acton.Env.initEnv (sysRoot paths) (nobuiltin args)
                                     env1 <- foldM (doTask args paths) env0 [t | AcyclicSCC t <- as]
                                     buildExecutable env1 args paths task
                                         `catch` handle Acton.Env.compilationError (src task) paths (name task)
                                     return ()
                              else do error ("********************\nCyclic imports:"++concatMap showCycle cs)
                                      System.Exit.exitFailure
  where isAcyclic (AcyclicSCC _) = True
        isAcyclic _              = False
        showCycle (CyclicSCC ts) = "\n"++concatMap (\t-> concat (intersperse "." (A.modPath (name t)))++" ") ts

chaseImportedFiles :: Args -> Paths -> [A.ModName] -> CompileTask -> IO [CompileTask]
chaseImportedFiles args paths imps task
                            = do newtasks <- catMaybes <$> mapM (readAFile [task]) imps
                                 chaseRecursively (task:newtasks) (map name newtasks) (concatMap importsOf newtasks)

  where readAFile tasks mn  = case lookUp mn tasks of    -- read and parse file mn in the project directory, unless it is already in tasks 
                                 Just t -> return Nothing
                                 Nothing -> case srcFile paths mn of
                                               Nothing -> return Nothing
                                               Just actFile -> do
                                                    ok <- System.Directory.doesFileExist actFile
                                                    if ok then do 
                                                        (src,m) <- Acton.Parser.parseModule mn actFile
                                                        return $ Just $ ActonTask mn src m
                                                     else
                                                        return Nothing
  
        lookUp mn (t : ts)
          | name t == mn     = Just t
          | otherwise        = lookUp mn ts
        lookUp _ []          = Nothing
        
        chaseRecursively tasks mns []
                             = return tasks
        chaseRecursively tasks mns (imn : imns)
                             = if imn `elem` mns
                                then chaseRecursively tasks mns imns
                                else do t <- readAFile tasks imn
                                        chaseRecursively (maybe tasks (:tasks) t)
                                                         (imn:mns)
                                                         (imns ++ concatMap importsOf t)


doTask :: Args -> Paths -> Acton.Env.Env0 -> CompileTask -> IO Acton.Env.Env0
doTask args paths env t@(ActonTask mn src m)
                            = do ok <- checkUptoDate paths actFile tyFile [hFile, cFile] (importsOf t)
                                 if ok && mn /= topMod paths then do
                                          iff (verbose args) (putStrLn ("Skipping  "++ actFile ++ " (files are up to date)."))
                                          return env
                                  else do touchDirs (sysRoot paths) mn
                                          iff (verbose args) (putStr ("Compiling "++ actFile ++ "... ") >> hFlush stdout)
                                          (env',te) <- runRestPasses args paths env m
                                                           `catch` handle generalError src paths mn
                                                           `catch` handle Acton.Env.compilationError src paths mn
                                          iff (verbose args) (putStrLn "Done.")
                                          return (Acton.Env.addMod mn te env')
  where Just actFile        = srcFile paths mn
        outbase             = sysFile paths mn
        tyFile              = outbase ++ ".ty"
        hFile               = outbase ++ ".h"
        cFile               = outbase ++ ".c"

checkUptoDate :: Paths -> FilePath -> FilePath -> [FilePath] -> [A.ModName] -> IO Bool
checkUptoDate paths actFile iFile outFiles imps
                        = do srcExists <- System.Directory.doesFileExist actFile
                             outExists <- mapM System.Directory.doesFileExist (iFile:outFiles)
                             if not (srcExists && and outExists) then return False
                              else do srcTime  <-  System.Directory.getModificationTime actFile
                                      outTimes <- mapM System.Directory.getModificationTime (iFile:outFiles)
                                      impsOK   <- mapM (impOK (head outTimes)) imps
                                      return (all (srcTime <) outTimes && and impsOK)
  where impOK iTime mn = do let impFile = sysFile paths mn ++ ".ty"
                            ok <- System.Directory.doesFileExist impFile
                            if ok then do impfileTime <- System.Directory.getModificationTime impFile
                                          return (impfileTime < iTime)
                             else error ("********************\nError: cannot find interface file "++impFile)


runRestPasses :: Args -> Paths -> Acton.Env.Env0 -> A.Module -> IO (Acton.Env.Env0, Acton.Env.TEnv)
runRestPasses args paths env0 parsed = do
                      let outbase = sysFile paths (A.modname parsed)
                      env <- Acton.Env.mkEnv (sysRoot paths) env0 parsed

                      kchecked <- Acton.Kinds.check env parsed
                      iff (kinds args) $ dump "kinds" (Pretty.print kchecked)

                      (iface,tchecked,typeEnv) <- Acton.Types.reconstruct outbase env kchecked
                      iff (types args) $ dump "types" (Pretty.print tchecked)
                      iff (sigs args) $ dump "sigs" (Pretty.vprint iface)

                      (normalized, normEnv) <- Acton.Normalizer.normalize typeEnv tchecked
                      iff (norm args) $ dump "norm" (Pretty.print normalized)
                      --traceM ("#################### normalized env0:")
                      --traceM (Pretty.render (Pretty.pretty normEnv))

                      (deacted,deactEnv) <- Acton.Deactorizer.deactorize normEnv normalized
                      iff (deact args) $ dump "deact" (Pretty.print deacted)
                      --traceM ("#################### deacted env0:")
                      --traceM (Pretty.render (Pretty.pretty deactEnv))

                      (cpstyled,cpsEnv) <- Acton.CPS.convert deactEnv deacted
                      iff (cps args) $ dump "cps" (Pretty.print cpstyled)
                      --traceM ("#################### cps'ed env0:")
                      --traceM (Pretty.render (Pretty.pretty cpsEnv))

                      (lifted,liftEnv) <- Acton.LambdaLifter.liftModule cpsEnv cpstyled
                      iff (llift args) $ dump "llift" (Pretty.print lifted)
                      --traceM ("#################### lifteded env0:")
                      --traceM (Pretty.render (Pretty.pretty liftEnv))

                      (h,c) <- Acton.CodeGen.generate liftEnv lifted

                      iff (not $ nobuiltin args) $ do
                          writeFile (outbase ++ ".h") h
                          writeFile (outbase ++ ".c") c
                          createProcess (proc "gcc" ["-c", "-I"++sysPath paths, outbase ++ ".c", "-o"++outbase++".o"])
                      iff (hgen args) $ dump "hgen (.h)" h
                      iff (cgen args) $ dump "cgen (.c)" c

                      return (env0 `Acton.Env.withModulesFrom` env,iface)


handle f src paths mn ex = do putStrLn "\n********************"
                              putStrLn (makeReport (f ex) fname src)
                              removeIfExists (outbase++".ty")
                              System.Exit.exitFailure
  where Just fname     = srcFile paths mn
        outbase        = sysFile paths mn
        removeIfExists f = trace ("#### REMOVING " ++ f) $ removeFile f `catch` handleExists
        handleExists :: IOException -> IO ()
        handleExists _ = return ()

makeReport (loc, msg) file src = errReport (sp, msg) src
  where sp = Acton.Parser.extractSrcSpan loc file src


buildExecutable env args paths task
  | null $ root args        = return ()
  | otherwise               = do putStrLn ("## root = " ++ prstr qn)
                                 putStrLn ("## " ++ prstr n ++ " : " ++ prstr sc)
                                 case Acton.Env.findQName qn env of
                                     i@(Acton.Env.NAct [] (A.TRow _ _ _ t A.TNil{}) A.TNil{} _) -> do
                                         putStrLn ("## Env is " ++ prstr t)
                                         c <- Acton.CodeGen.genRoot env qn t
                                         writeFile rootFile c
                                         createProcess (proc "gcc" $ ["-I"++sysPath paths, rootFile, objFile, "-o"++binFile] ++ libFiles)
                                     _ ->
                                         error ("********************\nRoot " ++ prstr n ++ " : " ++ prstr sc ++ " is not instantiable")
                                 return ()
  where n                   = A.name (root args)
        mn                  = name task
        qn                  = A.GName mn n
        (sc,_)              = Acton.QuickType.schemaOf env (A.eQVar qn)
        outbase             = sysFile paths mn
        rootFile            = outbase ++ ".root.c"
        objFile             = outbase ++ ".o"
        sysbase             = sysPath paths
        libFiles            = "-lutf8proc" : map (++".o") [joinPath [sysbase,"rts","rts"],joinPath [sysbase,"builtin","builtin"]]
        binFile             = dropExtension srcbase
        Just srcbase        = srcFile paths mn
