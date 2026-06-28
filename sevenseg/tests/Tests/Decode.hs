{- |
Tests for the pure decode ("SevenSeg.Decode").

The font is pinned as a full @0@–@F@ active-low truth table ('fontTable'): the
expected pattern is written as a 'BitVector' binary literal with segment @a@ as
the most-significant bit, so @unpack@ lands segment @a@ at 'Vec' index 0. Two
structural guards (no digit fully dark, all sixteen glyphs distinct) catch typos
independently of the exact glyphs.
-}
module Tests.Decode (decodeTests) where

import Prelude

import Test.Tasty
import Test.Tasty.HUnit

import qualified Clash.Prelude as C
import qualified Data.List as List

import SevenSeg.Decode (display, displayPorts, hexToSeg, nibbles, segToBus)

-- | Expected active-low patterns, index = hex digit. Each literal is
-- @0b a b c d e f g@ (segment a = MSB); @unpack@ puts a at 'Vec' index 0.
fontTable :: [C.Vec 7 C.Bit]
fontTable =
        map
                C.unpack
                ( [ 0b0000001 -- 0  a b c d e f
                  , 0b1001111 -- 1  b c
                  , 0b0010010 -- 2  a b d e g
                  , 0b0000110 -- 3  a b c d g
                  , 0b1001100 -- 4  b c f g
                  , 0b0100100 -- 5  a c d f g
                  , 0b0100000 -- 6  a c d e f g
                  , 0b0001111 -- 7  a b c
                  , 0b0000000 -- 8  a b c d e f g
                  , 0b0000100 -- 9  a b c d f g
                  , 0b0001000 -- A  a b c e f g
                  , 0b1100000 -- b  c d e f g
                  , 0b0110001 -- C  a d e f
                  , 0b1000010 -- d  b c d e g
                  , 0b0110000 -- E  a d e f g
                  , 0b0111000 -- F  a e f g
                  ] ::
                        [C.BitVector 7]
                )

-- | Indices of lit segments (active-low: lit ⇔ 'C.low').
litSegments :: C.Vec 7 C.Bit -> [Int]
litSegments v = [i | (i, x) <- List.zip [0 ..] (C.toList v), x == C.low]

decodeTests :: TestTree
decodeTests =
        testGroup
                "Decode"
                [ fontTests
                , structureTests
                , nibblesTests
                , displayTests
                , orderTests
                , alignmentTests
                ]

fontTests :: TestTree
fontTests =
        testGroup
                "hexToSeg font (active-low truth table)"
                [ testCase ("digit " ++ show i) $
                        hexToSeg (fromIntegral i) @?= expected
                | (i, expected) <- List.zip [0 :: Int ..] fontTable
                ]

structureTests :: TestTree
structureTests =
        testGroup
                "font structure (font-independent guards)"
                [ testCase "no digit is fully dark" $
                        assertBool
                                "some digit lit no segments"
                                (all (\d -> not (List.null (litSegments (hexToSeg d)))) [0 .. 15])
                , testCase "all sixteen glyphs are distinct" $
                        let glyphs = map hexToSeg [0 .. 15]
                        in List.length (List.nub glyphs) @?= 16
                , testCase "8 lights all seven segments" $
                        litSegments (hexToSeg 8) @?= [0 .. 6]
                , testCase "1 lights exactly b and c" $
                        litSegments (hexToSeg 1) @?= [1, 2]
                ]

-- | A handful of representative words reused across the contract tests.
sampleWords :: [C.Unsigned 16]
sampleWords = [0x0000, 0x0001, 0x1234, 0xABCD, 0xF0F0, 0xFFFF]

nibblesTests :: TestTree
nibblesTests =
        testGroup
                "nibbles (MSD-first)"
                [ testCase "splits 0x1234 MSD-first" $
                        nibbles 0x1234 @?= (0x1 C.:> 0x2 C.:> 0x3 C.:> 0x4 C.:> C.Nil)
                , testCase "round-trips through bitCoerce" $
                        [C.bitCoerce (nibbles v) | v <- sampleWords] @?= sampleWords
                ]

displayTests :: TestTree
displayTests =
        testCase "display == map hexToSeg . nibbles" $
                [display v | v <- sampleWords]
                        @?= [C.map hexToSeg (nibbles v) | v <- sampleWords]

orderTests :: TestTree
orderTests =
        testCase "displayPorts is port-order (index 0 = hex0 = LSD)" $
                displayPorts 0x1234
                        @?= C.map
                                (segToBus . hexToSeg)
                                (0x4 C.:> 0x3 C.:> 0x2 C.:> 0x1 C.:> C.Nil)

-- | A 'Vec 7 Bit' lit only at index @k@ (segment @k@), all others dark.
oneHotSeg :: Int -> C.Vec 7 C.Bit
oneHotSeg k = C.replace k C.high (C.repeat C.low)

alignmentTests :: TestTree
alignmentTests =
        testCase "segToBus aligns Vec index k to bus bit k" $
                [segToBus (oneHotSeg k) | k <- [0 .. 6]]
                        @?= [C.shiftL (1 :: C.BitVector 7) k | k <- [0 .. 6]]
