{- |
Tests for the odometer time base ("SevenSeg.Odometer").

All pure: 'odometerValue' is exercised at a small divider @K@ (so the wide
counter is only 20 bits and the arithmetic is easy to follow). The slice law
pins "value = high 16 bits"; the cadence cases pin the odometer behaviour — one
HEX0 tick per @2^K@ counts and a 16× ratio between adjacent digits.
-}
module Tests.Odometer (odometerTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C

import SevenSeg.Odometer (odometerValue)

-- | Small divider for the tests (the synthesized design uses 'DivBits').
type K = 4

-- | One HEX0 tick: the counter increment that bumps the value by 1.
stepSize :: C.Unsigned (16 C.+ K)
stepSize = C.shiftL 1 (C.natToNum @K)

-- | Expected high-slice: the top 16 bits of the wide counter.
hi16 :: C.Unsigned (16 C.+ K) -> C.Unsigned 16
hi16 c = C.resize (C.shiftR c (C.natToNum @K))

odometerTests :: TestTree
odometerTests =
        testGroup
                "Odometer"
                [ testCase "value is the high 16 bits of the counter" $
                        [odometerValue @K c | c <- counters] @?= [hi16 c | c <- counters]
                , testCase "advancing by 2^k bumps the value by exactly 1" $
                        odometerValue @K (base + stepSize) @?= odometerValue @K base + 1
                , testCase "HEX0 spins 16x faster than HEX1" $ do
                        odometerValue @K 0 @?= 0
                        odometerValue @K stepSize @?= 1
                        odometerValue @K (16 * stepSize) @?= 0x10
                ]
    where
        counters :: [C.Unsigned (16 C.+ K)]
        counters = [0, 1, stepSize, stepSize + 1, 17 * stepSize, 0xABCD * stepSize]
        base :: C.Unsigned (16 C.+ K)
        base = 0x123 * stepSize
