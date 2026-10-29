-- The yaml package (libyaml underneath): a document read into an aeson Value, which is what a
-- Haskell program asks of it.  The Value is walked to count its parts.
module Main (main) where

import qualified Data.Aeson as A
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Vector as V
import Data.Yaml (decodeEither')
import Timer (run)

size :: A.Value -> Int
size v = case v of
  A.Object o -> 1 + sum (map size (KM.elems o))
  A.Array a -> 1 + V.foldl' (\n x -> n + size x) 0 a
  A.String s -> s `seq` 1
  A.Number n -> n `seq` 1
  A.Bool b -> b `seq` 1
  A.Null -> 1

main :: IO ()
main = run $ \bs -> case decodeEither' bs of
  Left e -> Left (show e)
  Right v -> Right (size v)
