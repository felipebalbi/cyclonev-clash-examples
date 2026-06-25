import Prelude

import Test.Tasty

import qualified Tests.PwmCore

main :: IO ()
main =
        defaultMain $
                testGroup
                        "."
                        [ Tests.PwmCore.coreTests
                        ]
