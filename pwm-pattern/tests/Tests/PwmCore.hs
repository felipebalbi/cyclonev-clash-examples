{- |
Unit tests for "PwmCore".

The core is a free-running counter + comparator with a duty __shadow register__
and an __end-of-period__ tick. 'pwm' returns a @(led, endOfPeriod)@ pair of
signals; we 'C.bundle' them into one signal so 'C.sampleN' can sample both
together, then assert over the resulting list — pure Haskell, no Quartus.

We drive the core at a 4-bit width (16-cycle period) so several periods fit in a
short sample. Counting over /whole/ periods is phase-independent (any 16
consecutive counts of a mod-16 counter hit 0..15 once), and dropping the first
period(s) clears the reset warm-up — the same approach as @pwm/tests/Tests/Pwm.hs@.
-}
module Tests.PwmCore (coreTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import PwmCore (pwm)

-- | Width the tests drive 'pwm' at: 4 bits -> a 16-cycle PWM period.
type DutyWidth = 4

-- | Cycles in one PWM period (@2 ^ DutyWidth = 16@).
period :: Int
period = fromIntegral (maxBound :: C.Unsigned DutyWidth) + 1

{- | Sample @n@ cycles of the core driven by a __constant__ @duty@, in Clash's
'C.System' domain. 'pwm' returns a pair of signals; 'C.bundle' turns that into a
single @Signal dom (Bit, Bool)@ so 'C.sampleN' can sample @(led, endOfPeriod)@
together.
-}
coreSample :: Int -> C.Unsigned DutyWidth -> [(C.Bit, Bool)]
coreSample n d =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        C.bundle (pwm (C.pure d))

{- | Like 'coreSample', but the duty is a __time-varying__ stream: 'C.fromList'
turns the list into a 'C.Signal' (cycle @k@ takes element @k@). Used by the
shadow-latch test, where the duty changes mid-period.
-}
coreSampleFrom :: Int -> [C.Unsigned DutyWidth] -> [(C.Bit, Bool)]
coreSampleFrom n ds =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        C.bundle (pwm (C.fromList ds))

-- | Number of 'True's in a list of 'Bool's.
countTrues :: [Bool] -> Int
countTrues = List.length . List.filter id

-- | Number of 'C.high's in a list of 'C.Bit's.
countHighs :: [C.Bit] -> Int
countHighs = List.length . List.filter C.bitToBool

{- | The end-of-period (@snd@) stream over @periods@ whole periods of steady
state. The first period is dropped to clear the reset warm-up; because the
window is a whole number of periods, the result is alignment-independent: any
@16 * periods@ consecutive counts of the mod-16 counter hit each value (hence
@maxBound@) exactly @periods@ times.
-}
endOfPeriodOver :: Int -> [Bool]
endOfPeriodOver periods =
        List.take
                (periods * period)
                ( List.drop
                        period
                        (map snd (coreSample ((periods + 1) * period) 5))
                )

{- | The led (@fst@) stream over @periods@ whole periods, for a constant duty.
Two periods are dropped (not one): one for the reset warm-up and one for the
shadow register's startup latch (it powers up at 0 and only loads the real duty
at the first period boundary), so the remaining window is clean steady state.
-}
ledOver :: Int -> C.Unsigned DutyWidth -> [C.Bit]
ledOver periods d =
        List.take
                (periods * period)
                ( List.drop
                        (2 * period)
                        (map fst (coreSample ((periods + 2) * period) d))
                )

{- | Split the sampled stream into complete PWM periods (delimited by the
end-of-period tick) and count the led highs in each. The leading partial period
(before the first tick) is dropped, so every returned count covers a full period
during which the shadow duty was constant — hence a "clean" duty, never a blend.
-}
highsPerPeriod :: [(C.Bit, Bool)] -> [Int]
highsPerPeriod = List.drop 1 . go []
    where
        go _ [] = []
        go acc ((led, eop) : rest)
                | eop = countHighs (List.reverse (led : acc)) : go [] rest
                | otherwise = go (led : acc) rest

coreTests :: TestTree
coreTests =
        testGroup
                "PwmCore"
                [ -- 1. End-of-period: a 1-cycle pulse once per 16-cycle period, so
                  --    over 4 whole periods it fires 4 times. (Independent of duty,
                  --    hence the fixed 5 inside endOfPeriodOver.)
                  testCase "end-of-period pulses once per period" $
                        countTrues (endOfPeriodOver 4) @?= 4
                , -- 2. Duty exactness: a constant duty `d` drives the led high for
                  --    exactly `d` of every 16 cycles, so `4 * d` over 4 periods. A
                  --    *parameterised* test is a list of testCases, built by a
                  --    comprehension and spliced into the group with a nested
                  --    testGroup (cf. pwm/tests/Tests/Pwm.hs).
                  testGroup
                        "duty cycle is exact (led high for `duty` of every 16 cycles)"
                        [ testCase ("duty = " ++ show d) $
                                countHighs (ledOver 4 d) @?= 4 * fromIntegral d
                        | d <- [0, 4, 8, 15] :: [C.Unsigned DutyWidth]
                        ]
                , -- 3. Shadow latch (the point of this module): the duty steps 0 -> 8
                  --    *mid-period*. With the shadow register, every complete period
                  --    shows a clean duty (0 or 8) — the change is deferred to the
                  --    boundary — so no period is a blend. Without the shadow, the
                  --    period containing the step would show a partial count. We hold
                  --    duty 0 for two periods first so a clean 0-period is guaranteed
                  --    regardless of reset warm-up.
                  testCase "shadow register defers mid-period duty changes to the boundary" $ do
                        let counts =
                                highsPerPeriod
                                        ( coreSampleFrom
                                                (7 * period)
                                                (replicate (2 * period) 0 ++ repeat 8)
                                        )
                        assertBool
                                ("every complete period is a clean duty (0 or 8): " ++ show counts)
                                (all (`elem` [0, 8]) counts)
                        assertBool "the led eventually shows the new duty (8)" (8 `elem` counts)
                        assertBool "the led still shows the old duty (0) first" (0 `elem` counts)
                ]
