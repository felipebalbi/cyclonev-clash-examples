{- Wrapper around Clash's batch compiler, with the blinky project in scope.

   Generate Verilog with:

       stack run clash -- Blinky --verilog

   The HDL lands in verilog/Blinky.topEntity/. This file is taken verbatim
   from the upstream clash-starters projects. -}

import Clash.Main (defaultMain)
import System.Environment (getArgs)
import Prelude

main :: IO ()
main = getArgs >>= defaultMain
