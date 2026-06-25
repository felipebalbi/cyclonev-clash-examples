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
        ( PatGen (..)
        , PatGenMealy (..)
        , PatGenMoore (..)
        , prescale
        , runMealy
        , runMoore
        )
import PwmPattern.Pattern.Constant (Constant (..), constDuty)

patternTests :: TestTree
patternTests = testGroup "Pattern" [constantTests, prescaleTests]

-- ---------------------------------------------------------------------------
-- Constant
-- ---------------------------------------------------------------------------

constantTests :: TestTree
constantTests =
        testGroup
                "Constant"
                [ testCase "duty is the 75% default" $
                        duty (initial :: Constant) @?= constDuty
                , -- The field carries the level, so a chosen value flows straight through.
                  testCase "the field chooses the level" $
                        duty (Constant 12345) @?= 12345
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
