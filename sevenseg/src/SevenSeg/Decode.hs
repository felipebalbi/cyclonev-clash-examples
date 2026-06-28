{- |
The pure combinational decode: a hex nibble to its __active-low__ seven-segment
pattern, and the glue that splits a 16-bit word into four independently driven
digits.

No clock, no state — every function here is a plain combinational LUT/rewiring.
The board convention is __active-low__: a segment lights when its bit is @0@.
Bit/'Vec' index @i@ is segment @i@ with @0=a, 1=b, 2=c, 3=d, 4=e, 5=f, 6=g@,
matching C5G @HEX_i[i]@.
-}
module SevenSeg.Decode where

import Clash.Prelude

{- | Decode a hex digit to its active-low segment pattern (segment lit ⇔ bit
@0@), 'Vec' index @i@ = segment @i@ (@a..g@). The font is the conventional hex
glyph set; 'Tests.Decode' pins the full @0@–@F@ truth table.
-}
hexToSeg :: Unsigned 4 -> Vec 7 Bit
hexToSeg d = segTable !! d
    where
        segTable :: Vec 16 (Vec 7 Bit)
        segTable =
                map
                        unpack
                        $( listToVecTH
                                ( [ 0b0000001
                                  , 0b1001111
                                  , 0b0010010
                                  , 0b0000110
                                  , 0b1001100
                                  , 0b0100100
                                  , 0b0100000
                                  , 0b0001111
                                  , 0b0000000
                                  , 0b0000100
                                  , 0b0001000
                                  , 0b1100000
                                  , 0b0110001
                                  , 0b1000010
                                  , 0b0110000
                                  , 0b0111000
                                  ] ::
                                        [BitVector 7]
                                )
                         )

{- | Split a 16-bit word into four hex nibbles, __MSD-first__ (index 0 is the top
nibble): @nibbles 0x1234 == \<0x1,0x2,0x3,0x4\>@. A clean vector view of the word
— 'bitCoerce' reinterprets the 16 bits as four 4-bit lanes.
-}
nibbles :: Unsigned 16 -> Vec 4 (Unsigned 4)
nibbles = bitCoerce

{- | Decode a whole word to four active-low segment patterns, MSD-first
(@map hexToSeg . nibbles@). The 'Vec'-of-'Vec' decode, mirroring the per-lane
decode in @pwm-wave@.
-}
display :: Unsigned 16 -> Vec 4 (Vec 7 Bit)
display = map hexToSeg . nibbles

{- | Pack one digit's segment 'Vec' into the 'BitVector' that leaves the chip,
keeping the alignment __bus bit @k@ = segment @k@__ (so @hex_i[k]@ drives C5G
@HEX_i[k]@). Clash's 'v2bv' puts the 'Vec' head at the MSB, so the 'reverse'
lands segment @a@ (index 0) at bit 0; 'Tests.Decode' pins this.
-}
segToBus :: Vec 7 Bit -> BitVector 7
segToBus = pack . reverse

{- | Assemble the four digit buses in __port order__: index 0 = @hex0@ (the LSD,
rightmost display) … index 3 = @hex3@ (the MSD, leftmost). 'display' is MSD-first,
so the 'reverse' turns it into port order: value @0x1234@ shows @1@ on @hex3@ and
@4@ on @hex0@, reading @1234@ left-to-right on the board.
-}
displayPorts :: Unsigned 16 -> Vec 4 (BitVector 7)
displayPorts = reverse . map segToBus . display
