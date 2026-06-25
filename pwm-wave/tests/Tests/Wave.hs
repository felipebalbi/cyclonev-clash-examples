{- |
Tests for the wave layer ("PwmWave.Wave"): the brightness kernel and the
position ping-pong — both PURE (no clock; 'runWave' is exercised indirectly via
'waveNext'/'wavePos', which is all 'moore' clocks).

The kernel pins *shape*, not slope: 'triangleKernel' is the swappable waveform,
tunable on hardware by eye, so the tests assert "max at the peak, monotone
falloff, dark past the width" rather than specific brightness numbers. The
position machine reuses pwm-pattern's Triangle motion in position space; the
tests assert it ping-pongs by exactly 'posStep' between 0 and 'posMax' and never
wraps. The spatial-decode group checks the bump is centred, symmetric, and
clamped; the counter-rotation group checks green is red mirrored.
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
        , bumpVec
        , greenDuties
        , initialWave
        , kernelWidth
        , ledUnit
        , posMax
        , posStep
        , redDuties
        , triangleKernel
        , waveNext
        , wavePos
        )

waveTests :: TestTree
waveTests = testGroup "Wave" [kernelTests, decodeTests, counterRotationTests, positionTests]

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
-- spatial decode — one position -> a Vec of per-LED duties
-- ---------------------------------------------------------------------------

decodeTests :: TestTree
decodeTests =
        testGroup
                "spatial decode (bumpVec / redDuties)"
                [ -- With the peak sitting exactly on LED k, that LED is distance 0
                  --   from it, so it glows at full scale — for every k.
                  testCase "bump centred on the LED nearest the peak" $
                        [ C.toList (redDuties (fromIntegral k * ledUnit)) List.!! k
                        | k <- [0 .. 9]
                        ]
                                @?= List.replicate 10 (maxBound :: C.Unsigned DutyW)
                , -- The kernel depends only on |distance|, so the bump is symmetric:
                  --   LEDs equidistant either side of the peak match. (This is the
                  --   test that the unsigned-subtraction wrap would have broken.)
                  testCase "bump is symmetric about its peak" $ do
                        let v = C.toList (redDuties (3 * ledUnit)) -- peak on LED 3
                        v List.!! 2 @?= v List.!! 4
                        v List.!! 1 @?= v List.!! 5
                , -- Brightness decreases away from the peak.
                  testCase "brightness falls off with distance from the peak" $ do
                        let v = C.toList (redDuties (3 * ledUnit))
                        assertBool "lane 3 is the brightest" (v List.!! 3 >= v List.!! 2)
                        assertBool "nearer is brighter than farther" (v List.!! 2 >= v List.!! 1)
                , -- LEDs past the kernel width are dark.
                  testCase "far LEDs are dark" $ do
                        let v = C.toList (redDuties 0) -- peak on LED 0
                        assertBool "the far end is dark" (v List.!! 9 == 0)
                ]

-- ---------------------------------------------------------------------------
-- counter-rotation — green is red, mirrored
-- ---------------------------------------------------------------------------

counterRotationTests :: TestTree
counterRotationTests =
        testGroup
                "counter-rotation (green mirrors red)"
                [ -- The locked relationship: green's duties are the same bump
                  --   computed over green's 8 lanes, reversed.
                  testCase "green duties are red's bump, reversed" $
                        [ C.toList (greenDuties (fromIntegral k * ledUnit))
                        | k <- [0 .. 7]
                        ]
                                @?= [ reverse
                                        ( C.toList
                                                (bumpVec (fromIntegral k * ledUnit) :: C.Vec 8 (C.Unsigned DutyW))
                                        )
                                    | k <- [0 .. 7]
                                    ]
                , -- The consequence that makes the banks counter-rotate: when red's
                  --   peak is on LED k, green's peak is on the mirror LED (7 - k).
                  testCase "green peak sits at the mirror LED of red's" $
                        [ List.elemIndex
                                (maxBound :: C.Unsigned DutyW)
                                (C.toList (greenDuties (fromIntegral k * ledUnit)))
                        | k <- [0 .. 7]
                        ]
                                @?= [Just (7 - k) | k <- [0 .. 7]]
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
