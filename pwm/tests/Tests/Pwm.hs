{- |
Unit tests for "Pwm".

Where blinky was a fixed 50% square wave (the counter MSB), the PWM output's
high time is set by the duty input: the comparator holds the line high while the
free-running counter is below @duty@ and low above it — it "toggles after
crossing the duty threshold". So the property worth pinning down is the duty
cycle itself: the fraction of high samples.

We drive a tiny 4-bit counter (period = 16 cycles) so several periods fit in a
quick 'C.sampleN'. Counting highs over a /whole number of periods/ is
phase-independent: any 16 consecutive cycles of a mod-16 counter hit each value
0..15 exactly once, so exactly @duty@ of them sit below the threshold. We also
drop the first period to clear the reset warm-up, which makes the counts exact
regardless of how long 'C.resetGen' holds reset. No simulator — plain Haskell
over the sampled output stream, like blinky.
-}
module Tests.Pwm (pwmTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import Pwm (pwm)

-- | Counter width the tests drive 'pwm' at: 4 bits -> a 16-cycle PWM period.
type DutyWidth = 4

-- | Cycles in one PWM period (@2 ^ DutyWidth = 16@).
period :: Int
period = fromIntegral (maxBound :: C.Unsigned DutyWidth) + 1

{- | Sample @n@ cycles of the PWM output for a constant @duty@, in Clash's
default 'C.System' domain. 'pwm' takes the duty as a /signal/, so the constant is
lifted with 'pure'; the counter width (hence the period) follows from the duty's
type.
-}
pwmStream :: Int -> C.Unsigned DutyWidth -> [C.Bit]
pwmStream n d =
        C.sampleN @C.System
                n
                ( C.withClockResetEnable
                        C.clockGen
                        C.resetGen
                        C.enableGen
                        (pwm (pure d))
                )

{- | High samples over @periods@ whole PWM periods of steady state. The first
period is dropped to clear the reset warm-up; because complete periods are
phase-independent, the result is exactly @periods * duty@.
-}
highsOverPeriods :: Int -> C.Unsigned DutyWidth -> Int
highsOverPeriods periods d =
        countHighs
                ( List.take (periods * period)
                        (List.drop period (pwmStream ((periods + 1) * period) d))
                )

-- | Number of high (1) samples in a bit stream.
countHighs :: [C.Bit] -> Int
countHighs = List.length . List.filter C.bitToBool

-- | Number of @0 -> 1@ / @1 -> 0@ transitions in a bit stream.
countToggles :: [C.Bit] -> Int
countToggles xs =
        List.length (List.filter id (List.zipWith (/=) xs (List.drop 1 xs)))

pwmTests :: TestTree
pwmTests =
        testGroup
                "Pwm"
                [ -- The core property: over 4 whole periods the line is high for
                  -- exactly @duty@ cycles each, so @4 * duty@ in total. The sweep
                  -- covers 0%, 1/16, 25%, 50%, and the top step 15/16 — the
                  -- "never fully on" edge, since @2^n - 1@ is never < itself.
                  testGroup
                        "duty cycle is exact (high for `duty` of every 16 cycles)"
                        [ testCase ("duty = " ++ show d) $
                                highsOverPeriods 4 d @?= 4 * fromIntegral d
                        | d <- [0, 1, 4, 8, 15] :: [C.Unsigned DutyWidth]
                        ]
                  -- Sanity that it's a live, oscillating waveform (not stuck high
                  -- or low), the way blinky checked its LED toggled. This stream
                  -- includes the reset warm-up, so the bound is deliberately loose.
                , testCase "output oscillates each period (cf. blinky's toggle check)" $
                        assertBool
                                "expected the PWM line to toggle"
                                (countToggles (pwmStream 64 4) >= 2)
                ]
