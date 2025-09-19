import System.Posix.Signals
main = installHandler sigTERM Default Nothing >> putStrLn "Signal test"
