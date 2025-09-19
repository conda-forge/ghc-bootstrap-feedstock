import GHC.IO.Encoding
import GHC.IO.Encoding.Iconv
main = do
  enc <- mkTextEncoding "UTF-8"
  putStrLn $ "Encoding test: " ++ show enc
