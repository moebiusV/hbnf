-- The Alex/Happy JSON parser, timed: the lazy ByteString the lexer wants is made from the file's
-- strict one without a copy, and the result is walked to count its values.
module Main (main) where

import qualified Data.ByteString.Lazy as L
import Control.Exception (SomeException, evaluate, try)
import System.IO.Unsafe (unsafePerformIO)
import qualified Lexer
import Parser (JValue (..), parseJson)
import Timer (run)

size :: JValue -> Int
size v = case v of
  JObj kvs -> 1 + sum [ L.length k `seq` 1 + size x | (k, x) <- kvs ]
  JArr xs -> 1 + sum (map size xs)
  JStr s -> L.length s `seq` 1
  JNum s -> L.length s `seq` 1
  JBool b -> b `seq` 1
  JNull -> 1

main :: IO ()
main = run $ \bs -> unsafePerformIO $ do
  r <- try (evaluate (size (parseJson (alexScan (L.fromStrict bs)))))
  return (either (\e -> Left (show (e :: SomeException))) Right r)
  where alexScan = Lexer.alexScanTokens
