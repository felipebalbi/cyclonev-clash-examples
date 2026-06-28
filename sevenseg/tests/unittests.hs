import Prelude

import Test.Tasty

import qualified Tests.Decode
import qualified Tests.Odometer

main :: IO ()
main =
        defaultMain
                ( testGroup
                        "."
                        [ Tests.Decode.decodeTests
                        , Tests.Odometer.odometerTests
                        ]
                )
