import Prelude

import Test.Tasty

import qualified Tests.Pwm

main :: IO ()
main =
        defaultMain $
                testGroup
                        "."
                        [ Tests.Pwm.pwmTests
                        ]
