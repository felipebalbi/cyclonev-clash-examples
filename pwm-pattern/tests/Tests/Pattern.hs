{- |
Tests for the pattern-generator layer ("PwmPattern.Pattern" and its first
concrete pattern, "PwmPattern.Pattern.Constant").

Two groups:

  * __Constant__ — pure checks on the instance methods ('initial', 'next',
    'duty', 'step'), then a /simulated/ check that the 'runMoore' and 'runMealy'
    drivers (the first uses of 'C.moore' / 'C.mealyS' in this example) agree and
    hold a steady value.
  * __prescale__ — the tick divider, including the property that distinguishes it
    from a plain clock divider: it counts /ticks/, not clock cycles.
-}
module Tests.Pattern (patternTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import Control.Monad.State.Strict (runState)

import PwmPattern.Pattern
        ( DutyW
        , PatGen (..)
        , PatGenMealy (..)
        , PatGenMoore (..)
        , prescale
        , runMealy
        , runMoore
        )
import PwmPattern.Pattern.Constant (Constant (..), constDuty)
import PwmPattern.Pattern.Triangle (Triangle (..), scaleToDuty)

patternTests :: TestTree
patternTests =
        testGroup
                "Pattern"
                [constantTests, triangleTests, equivalenceTests, prescaleTests]

-- ---------------------------------------------------------------------------
-- Constant
-- ---------------------------------------------------------------------------

constantTests :: TestTree
constantTests =
        testGroup
                "Constant"
                [ testCase "duty is the 75% default" $
                        duty (initial :: Constant) @?= constDuty
                , testCase "never advances (next = id)" $
                        next (initial :: Constant) @?= (initial :: Constant)
                , -- step must yield the duty and leave the state untouched, whether or
                  -- not it is told to advance — a constant has no state to evolve. The
                  -- pair is (output, new-state); runState runs the State action.
                  testCase "step yields the duty and holds the state" $ do
                        runState (step True) (initial :: Constant)
                                @?= (constDuty, initial :: Constant)
                        runState (step False) (initial :: Constant)
                                @?= (constDuty, initial :: Constant)
                , -- First real use of the drivers: 'moore' and 'mealyS' must agree, and
                  -- because the state never moves the output is a flat constDuty line.
                  -- (A scaled-down preview of Task 5's full equivalence test.)
                  testCase "moore and mealy drivers agree on a constant stream" $ do
                        let n = 20
                            mooreStream =
                                C.sampleN @C.System n $
                                        C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                                                runMoore (initial :: Constant) (pure True)
                            mealyStream =
                                C.sampleN @C.System n $
                                        C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                                                runMealy (initial :: Constant) (pure True)
                        mooreStream @?= replicate n constDuty
                        mooreStream @?= mealyStream
                ]

-- ---------------------------------------------------------------------------
-- Triangle
-- ---------------------------------------------------------------------------

-- | The infinite sequence of Triangle states from the seed, advancing with 'next'.
triangleStates :: [Triangle]
triangleStates = iterate next (initial :: Triangle)

triangleTests :: TestTree
triangleTests =
        testGroup
                "Triangle"
                [ -- The level ramps 0,1,..,255 on the way up, so the first 256 duties
                  -- are exactly those levels scaled to the 16-bit range. `iterate next`
                  -- unrolls the state machine purely (no clock), and `map duty` reads
                  -- each state's brightness — a direct check of the rising half.
                  testCase "rising ramp: first 256 duties are levels 0..255 scaled" $
                        map duty (take 256 triangleStates)
                                @?= map scaleToDuty [0 .. 255]
                , -- After the peak the level falls 254,253,..,0 (the turnaround steps
                  -- *past* the top to 254, so 255 is visited once — no doubled tip).
                  -- Dropping the first 256 states lands us just past the peak.
                  testCase "falling ramp: next 255 duties are levels 254..0 scaled" $
                        map duty (take 255 (drop 256 triangleStates))
                                @?= map scaleToDuty (reverse [0 .. 254])
                , -- The re-authoring invariant: the Mealy `step` must match the Moore
                  -- `next`/`duty` at every state in a full period (510 states). With
                  -- advance=True the State action returns (duty s, next s); with
                  -- advance=False it returns (duty s, s) — output always the
                  -- *pre-update* duty, state held when not advancing.
                  testCase "step (advance=True) matches (duty, next) over a full period" $
                        [runState (step True) s | s <- take 510 triangleStates]
                                @?= [(duty s, next s) | s <- take 510 triangleStates]
                , testCase "step (advance=False) yields the duty and holds the state" $
                        [runState (step False) s | s <- take 510 triangleStates]
                                @?= [(duty s, s) | s <- take 510 triangleStates]
                , -- Simulated: the two drivers must produce identical waveforms. A
                  -- focused preview of Task 5; 600 cycles covers more than one period.
                  testCase "moore and mealy drivers agree (Triangle waveform)" $ do
                        let n = 600
                            mooreStream =
                                C.sampleN @C.System n $
                                        C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                                                runMoore (initial :: Triangle) (pure True)
                            mealyStream =
                                C.sampleN @C.System n $
                                        C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                                                runMealy (initial :: Triangle) (pure True)
                        mooreStream @?= mealyStream
                ]

-- ---------------------------------------------------------------------------
-- Equivalence (the "two spellings, one waveform" centrepiece)
-- ---------------------------------------------------------------------------

{- | Sample @n@ cycles of the Moore-driven Triangle under an arbitrary advance
tick, in 'C.System'. Monomorphic in the driver on purpose: a helper that took the
driver as an argument would let GHC generalise the domain away from 'C.System'
and become ambiguous, so 'runMoore' / 'runMealy' get their own helpers.
-}
mooreTriangle :: Int -> [Bool] -> [C.Unsigned DutyW]
mooreTriangle n ticks =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        runMoore (initial :: Triangle) (C.fromList ticks)

-- | As 'mooreTriangle', but Mealy-driven.
mealyTriangle :: Int -> [Bool] -> [C.Unsigned DutyW]
mealyTriangle n ticks =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        runMealy (initial :: Triangle) (C.fromList ticks)

equivalenceTests :: TestTree
equivalenceTests =
        testGroup
                "Equivalence"
                [ -- Guard the guard: an equivalence test passes vacuously if BOTH
                  -- drivers are identically broken (e.g. the pattern gets stuck at a
                  -- constant). Proving the waveform spans trough..peak shows it really
                  -- moves, so the agreement below is meaningful.
                  testCase "triangle waveform spans its full range (not vacuous)" $ do
                        let stream = mooreTriangle 600 (repeat True)
                        minimum stream @?= scaleToDuty minBound -- reaches the trough (0)
                        maximum stream @?= scaleToDuty maxBound -- reaches the peak
                , -- The existing agreement tests all advance every cycle (tick always
                  -- True). The drivers differ precisely in how they HOLD when not
                  -- advancing — runMoore's `if adv then next s else s` vs runMealy's
                  -- `when advance (put s')`. A gated tick exercises that hold path in
                  -- simulation through both drivers; they must still agree bit-for-bit.
                  testCase "drivers agree under a gated (intermittent) tick" $
                        let ticks = cycle [True, False, False, False] -- advance 1-in-4
                        in mooreTriangle 600 ticks @?= mealyTriangle 600 ticks
                ]

-- ---------------------------------------------------------------------------
-- prescale
-- ---------------------------------------------------------------------------

{- | Sample @n@ cycles of @prescale (SNat \@e)@ fed the given tick stream. The
output is a sub-sampled pulse train: one pulse per @2 ^ e@ /input pulses/.
-}
prescaleOut :: (C.KnownNat e) => C.SNat e -> [Bool] -> Int -> [Bool]
prescaleOut e ticks n =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        prescale e (C.fromList ticks)

-- | Indices at which a 'Bool' stream is 'True' (i.e. where pulses land).
trueIndices :: [Bool] -> [Int]
trueIndices bs = [i | (i, b) <- zip [0 ..] bs, b]

-- | Differences between consecutive elements — the spacing between pulses.
gaps :: [Int] -> [Int]
gaps xs = zipWith (-) (drop 1 xs) xs

{- | Assert every pulse gap equals @want@ (and that pulses exist to check). The
first pulse is dropped so reset warm-up can't skew the first gap.
-}
gapsAll :: Int -> [Bool] -> Assertion
gapsAll want out =
        let gs = gaps (drop 1 (trueIndices out))
        in assertBool
                ("gaps = " ++ show gs ++ ", want all " ++ show want)
                (not (null gs) && all (== want) gs)

prescaleTests :: TestTree
prescaleTests =
        testGroup
                "prescale"
                [ -- ÷1: every input pulse passes straight through.
                  testCase "exponent 0 is pass-through (÷1)" $
                        prescaleOut (C.SNat @0) (repeat True) 16 @?= replicate 16 True
                , -- ÷4 of a tick that fires every cycle => a pulse every 4 cycles.
                  testCase "exponent 2 divides an every-cycle tick by 4" $
                        gapsAll 4 (prescaleOut (C.SNat @2) (repeat True) 40)
                , -- The distinguishing property: a tick only every *other* cycle,
                  -- divided by 2 *ticks*, gives a pulse every 4 cycles — not every 2,
                  -- which is what dividing *cycles* would give. So prescale counts
                  -- ticks (the regEn is enabled by the tick, not free-running).
                  testCase "counts ticks, not clock cycles" $
                        gapsAll 4 (prescaleOut (C.SNat @1) (cycle [True, False]) 40)
                ]
