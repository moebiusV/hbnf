{-# LANGUAGE BangPatterns #-}
-- HsYAML (Herbert Valerio Riedel's pure Haskell YAML 1.2 parser): its event stream, the syntax alone,
-- as the hbnf YAML parsers are.  The stream is walked to the end and its events counted.
module Main (main) where

import qualified Data.ByteString.Lazy as L
import Data.YAML.Event (parseEvents)
import Timer (run)

main :: IO ()
main = run $ \bs -> go 0 (parseEvents (L.fromStrict bs))
  where
    go :: Int -> [Either e ev] -> Either String Int
    go !n [] = Right n
    go !_ (Left _ : _) = Left "refused"
    go !n (Right ev : rest) = ev `seq` go (n + 1) rest
