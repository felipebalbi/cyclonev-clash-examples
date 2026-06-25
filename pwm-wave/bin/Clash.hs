{- Wrapper around Clash's batch compiler, with the pwm-wave project in scope.

   Generate Verilog with:

       stack run clash -- PwmWave --verilog

   The HDL lands in verilog/PwmWave.topEntity/. This file is taken verbatim
   from the upstream clash-starters projects. -}

import Clash.Main (defaultMain)
import System.Environment (getArgs)
import Prelude

main :: IO ()
main = getArgs >>= defaultMain
