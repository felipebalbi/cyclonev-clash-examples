import Prelude

import Test.Tasty

import qualified Tests.Gamma
import qualified Tests.PwmWaveCore
import qualified Tests.Wave

main :: IO ()
main =
        defaultMain $
                testGroup
                        "."
                        [ Tests.PwmWaveCore.coreTests
                        , Tests.Wave.waveTests
                        , Tests.Gamma.gammaTests
                        ]
