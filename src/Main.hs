{- Main -- main entry point
Copyright (C) 2013  Benjamin Barenblat <bbaren@mit.edu>

This file is a part of decafc.

decafc is free software: you can redistribute it and/or modify it under the
terms of the MIT (X11) License as described in the LICENSE file.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the X11 license for more details. -}
module Main where

import Prelude hiding (readFile)
import qualified Prelude

import Control.Monad (void)
import Control.Monad.Error (ErrorT(..), runErrorT)
import Control.Monad.IO.Class (liftIO)
import Data.Either (partitionEithers)
import System.Environment (getProgName)
import qualified System.Exit
import System.IO (hPutStrLn, stderr)
import Text.Printf (printf)

import qualified CLI
import Configuration (Configuration, CompilerStage(..))
import qualified Configuration
import qualified Parser
import qualified Scanner


------------------------ Impure code: Fun with ErrorT -------------------------

main :: IO ()
main = do
  {- Compiler work can be split into three stages: reading input (impure),
  processing it (pure), and writing output (impure).  Of course, input might be
  malformed or there might be an error in processing.  Thus, it makes most
  sense to think of the compiler as having type ErrorT String IO [IO ()] --
  that is, computation might fail with a String or succeed with a series of IO
  actions. -}
  result <- runErrorT $ do
    -- Part I: Get input
    configuration <- ErrorT CLI.getConfiguration
    input <- readFile $ Configuration.input configuration
    -- Part II: Process it
    hoistEither $ process configuration input
  case result of
    -- Part III: Write output
    Left errorMessage -> fatal errorMessage
    Right actions -> sequence_ actions
  where hoistEither = ErrorT . return

readFile :: FilePath -> ErrorT String IO String
readFile name = liftIO $ Prelude.readFile name

fatal :: String -> IO ()
fatal message = do
  progName <- getProgName
  hPutStrLn stderr $ printf "%s: %s" progName message
  System.Exit.exitFailure


---------------------------- Pure code: Processing ----------------------------

{- The pure guts of the compiler convert input to output.  Exactly what output
they produce, though, depends on the configuration. -}
process :: Configuration -> String -> Either String [IO ()]
process configuration input =
  case Configuration.target configuration of
    Scan ->
      let tokensAndErrors = Scanner.scan input in
      let output = Scanner.formatTokensAndErrors tokensAndErrors in
      Right [ writeFile (Configuration.output configuration) output ]
    Parse -> do
      let (errors, tokens) = partitionEithers $ Scanner.scan input
      mapM_ Left errors         -- if errors occurred, bail out
      void $ Parser.parse tokens
      Right []
    phase -> Left $ show phase ++ " not implemented\n"
