-- toml-parser 1.3.2.0 (Eric Mertens) as Debian ships it: an Alex lexer and a Happy parser.
-- parseRawToml is the syntax alone, as the hbnf TOML parsers are (no duplicate-key check).
module Main (main) where

import qualified Data.ByteString.Char8 as C
import Data.List (foldl')
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NE
import Toml.Located (Located (..))
import Toml.Parser (Expr (..), Val (..), parseRawToml)
import Timer (run)

keySize :: NonEmpty (Located String) -> Int
keySize = foldl' (\n k -> n + length (locThing k)) 0 . NE.toList

valSize :: Val -> Int
valSize v = case v of
  ValArray vs -> 1 + foldl' (\n x -> n + valSize x) 0 vs
  ValTable kvs -> 1 + foldl' (\n (k, x) -> n + keySize k + valSize x) 0 kvs
  ValString s -> 1 + length s
  ValInteger i -> i `seq` 1
  ValFloat d -> d `seq` 1
  ValBool b -> b `seq` 1
  ValDay d -> d `seq` 1
  ValTimeOfDay d -> d `seq` 1
  ValZonedTime d -> d `seq` 1
  ValLocalTime d -> d `seq` 1

exprSize :: Expr -> Int
exprSize e = case e of
  KeyValExpr k v -> keySize k + valSize v
  TableExpr k -> keySize k
  ArrayTableExpr k -> keySize k

main :: IO ()
main = run $ \bs -> case parseRawToml (C.unpack bs) of
  Left (Located _ msg) -> Left msg
  Right es -> Right (foldl' (\n e -> n + exprSize e) 0 es)
