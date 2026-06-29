import Prelude

import Test.Tasty

import qualified Tests.Button

main :: IO ()
main =
        defaultMain
                ( testGroup
                        "."
                        [ Tests.Button.buttonTests
                        ]
                )
