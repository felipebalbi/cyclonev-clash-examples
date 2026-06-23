import Prelude

import Test.Tasty

import qualified Tests.Blinky

main :: IO ()
main =
        defaultMain $
                testGroup
                        "."
                        [ Tests.Blinky.blinkyTests
                        ]
