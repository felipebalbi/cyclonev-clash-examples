{- |
Tests for the wave layer ("PwmWave.Wave"): the brightness kernel and the
position ping-pong — both PURE (no clock; 'runWave' is exercised indirectly via
'waveNext'/'wavePos', which is all 'moore' clocks).

The kernel pins *shape*, not slope: 'triangleKernel' is the swappable waveform,
tunable on hardware by eye, so the tests assert "max at the peak, monotone
falloff, dark past the width" rather than specific brightness numbers. The
position machine reuses pwm-pattern's Triangle motion in position space; the
tests assert it ping-pongs by exactly 'posStep' between 0 and 'posMax' and never
wraps.

(The spatial decode + counter-rotation groups are added in the next task,
alongside 'bumpVec'/'redDuties'/'greenDuties'.)
-}
module Tests.Wave (waveTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import PwmWave.Wave
        ( DutyW
        , Position
        , initialWave
        , kernelWidth
        , ledUnit
        , posMax
        , posStep
        , triangleKernel
        , waveNext
        , wavePos
        )

waveTests :: TestTree
waveTests = testGroup "Wave" [kernelTests, positionTests]

-- ---------------------------------------------------------------------------
-- triangleKernel — the brightness falloff (shape, not slope)
-- ---------------------------------------------------------------------------

kernelTests :: TestTree
kernelTests =
        testGroup
                "triangleKernel"
                [ testCase "full brightness at the peak (distance 0)" $
                        triangleKernel 0 @?= (maxBound :: C.Unsigned DutyW)
                , testCase "dark at and beyond the kernel width" $
                        assertBool
                                "kernel must be 0 from kernelWidth outward"
                                (all (\d -> triangleKernel d == 0) [kernelWidth .. kernelWidth + ledUnit])
                , testCase "monotonically non-increasing with distance" $ do
                        let ks = map triangleKernel [0 .. kernelWidth]
                        assertBool
                                ("not monotone: " ++ show ks)
                                (and (List.zipWith (>=) ks (List.drop 1 ks)))
                , testCase "partly lit strictly between the peak and the width" $
                        let d = kernelWidth `div` 2
                        in assertBool
                                "midpoint should be dimmer than the peak but still lit"
                                (triangleKernel d > 0 && triangleKernel d < maxBound)
                ]

-- ---------------------------------------------------------------------------
-- position ping-pong
-- ---------------------------------------------------------------------------

-- | The position sequence from the seed, advancing every tick.
positions :: [Position]
positions = map wavePos (iterate waveNext initialWave)

-- | A horizon spanning a couple of full bounces, in cycles.
horizon :: Int
horizon = 4 * (fromIntegral posMax `div` fromIntegral posStep) + 4

-- | @|a - b|@ on the unsigned position type.
absDiff :: Position -> Position -> Position
absDiff a b = if a >= b then a - b else b - a

positionTests :: TestTree
positionTests =
        testGroup
                "position ping-pong"
                [ testCase "starts at 0" $
                        List.head positions @?= 0
                , testCase "every step moves by exactly posStep (never wraps/teleports)" $ do
                        let diffs = List.take horizon (List.zipWith absDiff positions (List.drop 1 positions))
                        assertBool
                                ("a step jumped by something other than posStep: " ++ show (List.take 40 diffs))
                                (all (== posStep) diffs)
                , testCase "stays within [0, posMax]" $
                        assertBool
                                "position left its bounds"
                                (all (\p -> p <= posMax) (List.take horizon positions))
                , testCase "reaches posMax then returns to 0 (a full bounce)" $ do
                        let bounce = List.take horizon positions
                            afterPeak = List.dropWhile (/= posMax) bounce
                        assertBool "never reached the far end (posMax)" (posMax `elem` bounce)
                        assertBool "did not return to 0 after the peak" (0 `elem` List.drop 1 afterPeak)
                , testCase "reverses at posMax (steps down, does not wrap to 0)" $ do
                        let afterPeak = List.dropWhile (/= posMax) positions
                        assertBool
                                "did not step down by posStep right after the peak"
                                (case afterPeak of a : b : _ -> b == a - posStep; _ -> False)
                ]
