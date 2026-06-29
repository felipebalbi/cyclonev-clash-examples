{- |
Tests for the three pushbutton primitives ("PushButton.Button") and the whole
@key0 -> led@ toggle ("PushButton.topEntity").

All pure: each circuit is a function from an input 'C.Signal' to an output
'C.Signal', so we drive a known stimulus with 'C.fromList', 'C.sampleN' the
output, and compare in plain Haskell — no FPGA, no Quartus. Everything runs in
the real 'Dom50' domain via @withClockResetEnable clockGen resetGen enableGen@.

The end-to-end cases ('polarityTests' \/ the capstone) __count toggles over a
settled window__ rather than pinning exact cycle positions, so they are robust to
the synchronizer's power-up level and to the pipeline latency. We drop a short
warm-up before counting: 'Dom50' asserts reset on cycle 0, and a synchronizer
seeded to the @pressed@ level would emit one phantom edge at power-up — neither is
a real button press, so neither should be counted.
-}
module Tests.Button (buttonTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import PushButton (topEntity)
import PushButton.Button (risingEdge, synchronize, toggleOn)
import PushButton.Domain (Dom50)

{- | Run a single-input synchronous circuit in 'Dom50': feed @xs@ in, sample @n@
output cycles. 'C.resetGen' asserts reset on cycle 0; 'C.enableGen' is always on.
-}
sim ::
        (C.NFDataX a, C.NFDataX b) =>
        (C.HiddenClockResetEnable Dom50 => C.Signal Dom50 a -> C.Signal Dom50 b) ->
        [a] ->
        Int ->
        [b]
sim f xs n =
        C.sampleN
                n
                (C.withClockResetEnable C.clockGen C.resetGen C.enableGen (f (C.fromList xs)))

-- | Sample @n@ cycles of the whole top entity driven by a @key0@ pin waveform.
-- 'topEntity' bakes in its own (de-asserted) reset and enable, so it takes only
-- the generated clock and the pin stream.
topOut :: [C.Bit] -> Int -> [C.Bit]
topOut presses n = C.sampleN n (topEntity C.clockGen (C.fromList presses))

-- | Number of @0 -> 1@ \/ @1 -> 0@ transitions in a stream (after dropping a
-- warm-up window). One toggle per LED flip.
togglesAfter :: (Eq a) => Int -> [a] -> Int
togglesAfter w xs =
        let ys = List.drop w xs
         in List.length (List.filter id (List.zipWith (/=) ys (List.drop 1 ys)))

-- | Active-low @key0@ levels, named for readability in the waveforms below.
released, pressed :: C.Bit
released = C.high
pressed = C.low

-- | Cycles to ignore before counting toggles: covers the cycle-0 reset and any
-- synchronizer power-up settling (see the module header).
warmup :: Int
warmup = 6

buttonTests :: TestTree
buttonTests =
        testGroup
                "Button"
                [ synchronizeTests
                , risingEdgeTests
                , toggleOnTests
                , polarityTests
                , capstoneTests
                ]

-- | 'synchronize': a pure 2-cycle delay. The output equals the input delayed by
-- exactly two cycles, so dropping the first two samples lines it up with the
-- input — independent of whatever the two flip-flops are seeded to (the seed only
-- shows in the two dropped samples).
synchronizeTests :: TestTree
synchronizeTests =
        testGroup
                "synchronize"
                [ testCase "output is the input delayed by exactly 2 cycles" $
                        List.drop 2 (sim synchronize inBits 12) @?= List.take 10 inBits
                ]
    where
        inBits :: [C.Bit]
        inBits =
                [ C.high, C.high, C.low, C.low, C.high, C.low
                , C.high, C.high, C.low, C.low, C.high, C.low
                ]

-- | 'risingEdge': exactly one one-cycle pulse on each @False -> True@, and quiet
-- otherwise — quiet while the input holds steady (high or low) and quiet on a
-- falling edge. The stimulus starts 'False' so the result is independent of the
-- detector's @prev@ seed.
risingEdgeTests :: TestTree
risingEdgeTests =
        testGroup
                "risingEdge"
                [ testCase "one pulse per rising edge, quiet while steady" $
                        sim risingEdge inBools 12 @?= expected
                ]
    where
        --        0      1      2     3     4     5      6      7     8      9    10    11
        inBools = [False, False, True, True, True, False, False, True, False, True, True, False]
        expected = [False, False, True, False, False, False, False, True, False, True, False, False]

-- | 'toggleOn': a T flip-flop seeded 'C.low'. Each 'True' pulse flips the stored
-- bit on the following cycle; every other cycle holds. The output is the
-- /registered/ bit, so a toggle appears one cycle after its pulse and the stream
-- starts 'C.low' (the LED powers up off).
toggleOnTests :: TestTree
toggleOnTests =
        testGroup
                "toggleOn"
                [ testCase "alternates on each pulse, holds between, starts low" $
                        sim toggleOn inPulses 10 @?= expected
                ]
    where
        --          0      1     2      3      4     5      6     7     8      9
        inPulses = [False, True, False, False, True, False, True, True, False, False]
        expected =
                [ C.low, C.low, C.high, C.high, C.high
                , C.low, C.low, C.high, C.low, C.low
                ]

-- | Polarity: the button is __active-low__, so a /press/ is a falling edge of the
-- pin (and a rising edge of @pressed@ after the invert). A press must toggle the
-- LED; the release that follows, and a steadily-released pin, must not.
polarityTests :: TestTree
polarityTests =
        testGroup
                "polarity (active-low: a press is a pin falling edge)"
                [ testCase "a steadily-released button never toggles the LED" $
                        togglesAfter warmup (topOut idle 16) @?= 0
                , testCase "one press toggles once; its release does not toggle again" $
                        togglesAfter warmup (topOut onePress 16) @?= 1
                ]
    where
        idle = List.replicate 16 released
        -- 6 released (warm-up), 4 pressed, 6 released: a single press then release.
        onePress =
                List.replicate 6 released
                        ++ List.replicate 4 pressed
                        ++ List.replicate 6 released

-- | Capstone: drive a realistic press waveform through the whole @key0 -> led@
-- pipeline and assert the LED toggles exactly once per __new__ press. The middle
-- press is __held__ for eight cycles and must still cause a single toggle — a
-- held button is one edge, not many.
capstoneTests :: TestTree
capstoneTests =
        testGroup
                "capstone (key0 -> led)"
                [ testCase "one toggle per new press; a held press is ignored" $
                        togglesAfter warmup (topOut presses 34) @?= 3
                ]
    where
        presses =
                List.replicate 6 released -- warm-up
                        ++ List.replicate 3 pressed -- press 1
                        ++ List.replicate 4 released
                        ++ List.replicate 8 pressed -- press 2, HELD
                        ++ List.replicate 4 released
                        ++ List.replicate 3 pressed -- press 3
                        ++ List.replicate 6 released
