{- |
Tests for "PwmWave.Gamma": the compile-time gamma table, the ROM-backed kernel,
and that gamma actually darkens the mid-tones relative to the linear triangle.
All pure — the table is constant-folded and 'gammaKernel' is combinational.
-}
module Tests.Gamma (gammaTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import PwmWave.Gamma (gammaCorrect, gammaKernel, gammaTable)
import PwmWave.Wave (DutyW, bumpVec, greenDuties, kernelWidth, ledUnit, triangleKernel)

gammaTests :: TestTree
gammaTests =
        testGroup
                "Gamma"
                [tableTests, kernelShapeTests, darkenTests, counterRotationGammaTests]

-- | The compile-time gamma curve.
tableTests :: TestTree
tableTests =
        testGroup
                "gammaTable"
                [ testCase "maps zero intensity to 0" $
                        List.head (C.toList gammaTable) @?= 0
                , testCase "maps full intensity to maxBound" $
                        List.last (C.toList gammaTable) @?= (maxBound :: C.Unsigned DutyW)
                , testCase "monotone non-decreasing" $
                        let xs = C.toList gammaTable
                        in assertBool
                                ("not monotone: " ++ show xs)
                                (and (List.zipWith (<=) xs (List.drop 1 xs)))
                ]

-- | 'gammaKernel' obeys the same shape laws as the triangle (it shares its support).
kernelShapeTests :: TestTree
kernelShapeTests =
        testGroup
                "gammaKernel shape"
                [ testCase "full brightness at the peak (distance 0)" $
                        gammaKernel 0 @?= (maxBound :: C.Unsigned DutyW)
                , testCase "dark at and beyond the kernel width" $
                        assertBool
                                "gammaKernel must be 0 from kernelWidth outward"
                                (all (\d -> gammaKernel d == 0) [kernelWidth .. kernelWidth + ledUnit])
                , testCase "monotonically non-increasing with distance" $
                        let ks = map gammaKernel [0 .. kernelWidth]
                        in assertBool
                                ("not monotone: " ++ show ks)
                                (and (List.zipWith (>=) ks (List.drop 1 ks)))
                ]

-- | The point of v2: gamma is never brighter than the linear triangle, equal only
-- at the peak, and strictly dimmer somewhere in the body (so it is not a no-op).
darkenTests :: TestTree
darkenTests =
        testGroup
                "gamma darkens the mid-tones"
                [ testCase "equal to the triangle at the peak" $
                        gammaKernel 0 @?= triangleKernel 0
                , testCase "never brighter than the triangle" $
                        assertBool
                                "gamma exceeded the triangle somewhere"
                                (all (\d -> gammaKernel d <= triangleKernel d) [0 .. kernelWidth])
                , testCase "strictly dimmer somewhere in the mids (non-vacuous)" $
                        assertBool
                                "gamma never darkened anything"
                                (any (\d -> gammaKernel d < triangleKernel d) [0 .. kernelWidth])
                ]

-- | Gamma is a per-lane 'C.map', so it commutes with green's 'reverse' — the
-- counter-rotation still holds for the gamma-corrected duties.
counterRotationGammaTests :: TestTree
counterRotationGammaTests =
        testGroup
                "counter-rotation under gamma"
                [ testCase "gamma-corrected green is gamma-corrected red, reversed" $
                        [ C.toList (C.map gammaCorrect (greenDuties (fromIntegral k * ledUnit)))
                        | k <- [0 .. 7]
                        ]
                                @?= [ reverse
                                        ( C.toList
                                                ( C.map
                                                        gammaCorrect
                                                        (bumpVec (fromIntegral k * ledUnit) :: C.Vec 8 (C.Unsigned DutyW))
                                                )
                                        )
                                    | k <- [0 .. 7]
                                    ]
                ]
