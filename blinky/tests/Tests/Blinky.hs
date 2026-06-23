{- |
Unit test for "Blinky".

Blinky has no data inputs (it is a pure clock divider), so there is nothing to
property-test with random stimulus the way the upstream orangecrab @blink@
example does. Instead we check the one observable behaviour deterministically:
driven for several short periods, the LED output actually toggles.

Because the circuit /is/ a function from the (empty) input stream to an output
stream, we test it with plain Haskell — 'sampleN' the output and count
transitions. No simulator, no testbench harness. The test is independent of the
Quartus toolchain entirely.
-}
module Tests.Blinky (blinkyTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import Blinky (blink)

{- | Sample @n@ cycles of the LED output with a tiny 4-bit counter (so the MSB
toggles every @2 ^ 3 = 8@ cycles and a handful of periods fit in @n@). The
circuit is run in Clash's default 'C.System' domain; its @resetGen@ holds
the counter at 0 for the first cycle, after which it free-runs.
-}
ledStream :: Int -> [C.Bit]
ledStream n =
        C.sampleN @C.System
                n
                ( C.withClockResetEnable
                        C.clockGen
                        C.resetGen
                        C.enableGen
                        (blink (C.SNat @4))
                )

-- | Number of @0 -> 1@ / @1 -> 0@ transitions in a bit stream.
countToggles :: [C.Bit] -> Int
countToggles xs =
        List.length (List.filter id (List.zipWith (/=) xs (List.drop 1 xs)))

blinkyTests :: TestTree
blinkyTests =
        testGroup
                "Blinky"
                [ testCase "LED toggles over several periods" $ do
                        let toggles = countToggles (ledStream 64)
                        assertBool
                                ("expected the LED to toggle at least twice, saw " ++ show toggles)
                                (toggles >= 2)
                ]
