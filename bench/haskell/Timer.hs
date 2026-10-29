-- Timer.hs -- what every Haskell driver shares: read the file, time one parse, report.
--
--   prog FILE         one parse, the clock around it, "ok BYTES MS RSS_KIB" (or "FAIL ...", exit 1)
--   prog -c FILE...   for each file "FILE 1" when the parser accepts it, "FILE 0" when it refuses
--
-- A parser gives back a count of what it found (the whole result is walked, so nothing is left
-- unevaluated when the clock stops), or the reason it refused.
module Timer (run) where

import qualified Data.ByteString as B
import Control.Exception (evaluate)
import GHC.Clock (getMonotonicTimeNSec)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

peakKiB :: IO Int
peakKiB = do
  s <- readFile "/proc/self/status"
  let ls = [ words l | l <- lines s, take 6 l == "VmHWM:" ]
  case ls of
    ((_ : n : _) : _) -> return (read n)
    _ -> return 0

run :: (B.ByteString -> Either String Int) -> IO ()
run parse = do
  args <- getArgs
  case args of
    ("-c" : files) -> mapM_ check files
    [file] -> do
      bs <- B.readFile file
      _ <- evaluate (B.length bs)
      t0 <- getMonotonicTimeNSec
      r <- evaluate (parse bs)
      t1 <- getMonotonicTimeNSec
      rss <- peakKiB
      let ms = fromIntegral (t1 - t0) / 1e6 :: Double
      case r of
        Left e -> do
          hPutStrLn stderr e
          putStrLn ("FAIL " ++ show (B.length bs) ++ " " ++ show ms ++ " " ++ show rss)
          exitFailure
        Right n -> n `seq` putStrLn ("ok " ++ show (B.length bs) ++ " " ++ show (fromIntegral (round (ms * 100) :: Int) / 100 :: Double) ++ " " ++ show rss)
    _ -> hPutStrLn stderr "usage: prog FILE | prog -c FILE..." >> exitFailure
  where
    check f = do
      bs <- B.readFile f
      r <- evaluate (parse bs)
      putStrLn (f ++ " " ++ either (const "0") (const "1") r)
