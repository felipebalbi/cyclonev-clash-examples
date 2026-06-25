{- |
Unit tests for "PwmWave.Core".

'pwmVec' is the vectorized PWM core: ONE free-running carrier counter compared
against a 'Vec' of per-lane duties, the whole 'Vec' shadow-latched at the period
boundary, plus the shared end-of-period tick. It returns
@(Signal dom (Vec n Bit), Signal dom Bool)@; we 'C.bundle' the pair so 'C.sampleN'
samples the led-vector and the eop together.

We drive a 4-bit carrier (16-cycle period) with a 3-lane duty vector so several
whole periods fit in a short sample. Counting highs over WHOLE periods is
phase-independent (any 16 consecutive counts of a mod-16 counter hit 0..15 once),
and dropping the warm-up periods clears the reset + shadow-latch startup — the
same approach as @pwm/tests/Tests/Pwm.hs@ and @pwm-pattern@'s core tests, now
per-lane.
-}
module Tests.PwmWaveCore (coreTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import PwmWave.Core (pwmVec)

-- | Carrier width the tests drive 'pwmVec' at: 4 bits -> a 16-cycle period.
type DutyWidth = 4

-- | Number of PWM lanes under test.
type Lanes = 3

-- | Cycles in one PWM period (@2 ^ DutyWidth = 16@).
period :: Int
period = fromIntegral (maxBound :: C.Unsigned DutyWidth) + 1

-- | A representative constant duty vector for the per-lane and eop tests.
duties :: C.Vec Lanes (C.Unsigned DutyWidth)
duties = 3 C.:> 8 C.:> 15 C.:> C.Nil

{- | Sample @n@ cycles of 'pwmVec' driven by a CONSTANT duty vector, in
'C.System'. 'C.bundle' turns the @(leds, eop)@ pair of signals into one
@Signal dom (Vec Lanes Bit, Bool)@ so 'C.sampleN' samples them together.
-}
coreSample :: Int -> C.Vec Lanes (C.Unsigned DutyWidth) -> [(C.Vec Lanes C.Bit, Bool)]
coreSample n ds =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        C.bundle (pwmVec (C.pure ds))

{- | As 'coreSample', but the duty vector is time-varying ('C.fromList'): cycle
@k@ takes element @k@. Used by the shadow-latch test, where one lane's duty
changes mid-period.
-}
coreSampleFrom :: Int -> [C.Vec Lanes (C.Unsigned DutyWidth)] -> [(C.Vec Lanes C.Bit, Bool)]
coreSampleFrom n dss =
        C.sampleN @C.System n $
                C.withClockResetEnable C.clockGen C.resetGen C.enableGen $
                        C.bundle (pwmVec (C.fromList dss))

-- | Number of 'True's in a list.
countTrues :: [Bool] -> Int
countTrues = List.length . List.filter id

-- | Number of 'C.high's in a 'C.Bit' list.
countHighs :: [C.Bit] -> Int
countHighs = List.length . List.filter C.bitToBool

-- | Pull lane @i@'s bit out of each sampled led-vector.
laneBits :: Int -> [(C.Vec Lanes C.Bit, Bool)] -> [C.Bit]
laneBits i = map (\(v, _) -> C.toList v List.!! i)

{- | Highs in lane @i@ over @periods@ whole periods, for a constant duty vector.
Two periods are dropped (reset warm-up + the shadow register's startup latch,
which powers up at 0 and only loads the real duty at the first boundary).
-}
laneHighsOver :: Int -> Int -> C.Vec Lanes (C.Unsigned DutyWidth) -> Int
laneHighsOver periods i ds =
        countHighs
                ( List.take (periods * period)
                        ( List.drop (2 * period)
                                (laneBits i (coreSample ((periods + 2) * period) ds))
                        )
                )

-- | The eop (snd) stream over @periods@ whole periods (drop the warm-up period).
eopOver :: Int -> [Bool]
eopOver periods =
        List.take (periods * period)
                ( List.drop period
                        (map snd (coreSample ((periods + 1) * period) duties))
                )

{- | Split a (led, eop) stream into complete PWM periods and count the highs in
each. The leading partial period (before the first eop) is dropped, so every
returned count covers a full period during which the shadow duty was constant.
-}
highsPerPeriod :: [C.Bit] -> [Bool] -> [Int]
highsPerPeriod leds eops = List.drop 1 (go [] (List.zip leds eops))
    where
        go _ [] = []
        go acc ((led, eop) : rest)
                | eop = countHighs (List.reverse (led : acc)) : go [] rest
                | otherwise = go (led : acc) rest

coreTests :: TestTree
coreTests =
        testGroup
                "PwmWaveCore"
                [ -- 1. End-of-period: a 1-cycle pulse once per 16-cycle period, so
                  --    over 4 whole periods it fires 4 times.
                  testCase "end-of-period pulses once per period" $
                        countTrues (eopOver 4) @?= 4
                , -- 2. Per-lane duty exactness: lane i is high for exactly its own
                  --    duty of every 16 cycles, independent of the other lanes — the
                  --    point of N independent comparators off one carrier.
                  testGroup
                        "each lane high for its own duty (whole-period count)"
                        [ testCase ("lane " ++ show i ++ ", duty " ++ show d) $
                                laneHighsOver 4 i duties @?= 4 * fromIntegral d
                        | (i, d) <- List.zip [0 ..] (C.toList duties)
                        ]
                , -- 3. Vec shadow latch (the point of the vectorized shadow): lane 0's
                  --    duty steps 0 -> 8 *mid-period*. With the Vec shadow register,
                  --    every COMPLETE period shows a clean duty (0 or 8), never a
                  --    blend. Hold 0 for two periods first so a clean 0-period is
                  --    guaranteed regardless of reset warm-up.
                  testCase "Vec shadow latches the whole vector at the boundary" $ do
                        let dss =
                                List.replicate (2 * period) (C.repeat 0)
                                        ++ List.repeat (8 C.:> 0 C.:> 0 C.:> C.Nil)
                            sampled = coreSampleFrom (7 * period) dss
                            counts = highsPerPeriod (laneBits 0 sampled) (map snd sampled)
                        assertBool
                                ("every complete period is a clean duty (0 or 8): " ++ show counts)
                                (all (`elem` [0, 8]) counts)
                        assertBool "lane eventually shows the new duty (8)" (8 `elem` counts)
                        assertBool "lane still shows the old duty (0) first" (0 `elem` counts)
                ]
