{- |
The __gamma__ brightness kernel — and the repo's first on-chip ROM.

The v1 'PwmWave.Wave.triangleKernel' falls off linearly in /duty/, but LED
brightness perception is roughly gamma, so a linear bump's neighbours read as
nearly as bright as its peak. This module re-maps the triangle's output through a
__gamma curve__ so the falloff /looks/ even: @gammaKernel = gammaCorrect .
triangleKernel@. Same bump geometry as the triangle (same support, same peak);
only the brightness mapping changes. 'PwmWave' selects triangle vs gamma at
runtime on @SW0@.

The curve lives in a compile-time table read by 'Clash.Prelude.asyncRomPow2' — a
combinational on-chip ROM, so 'gammaKernel' stays a pure drop-in for the decode.
-}
module PwmWave.Gamma where

import Clash.Prelude
import PwmWave.Wave (DutyW, Position, triangleKernel)

{- | The gamma curve, baked at __compile time__: @table[i] = (i/255) ^ 2.2 ·
maxBound@, a 256-entry intensity→duty map. It /must/ be compile-time — the
@** 2.2@ is 'Double' math with no hardware form — so it is built with
'Clash.Prelude.listToVecTH', which splices the values in as a literal 'Vec'. By
construction @table[0] = 0@, @table[255] = maxBound@, monotone non-decreasing.
Change the @2.2@ to retune the curve.
-}
gammaTable :: Vec 256 (Unsigned DutyW)
gammaTable =
        $( listToVecTH
                [ round ((fromIntegral i / 255 :: Double) ** 2.2 * fromIntegral (maxBound :: Unsigned DutyW)) ::
                        Unsigned DutyW
                | i <- [0 .. 255 :: Int]
                ]
         )

{- | The gamma curve as a combinational on-chip ROM. 'asyncRomPow2' fits exactly:
256 = @2 ^ 8@ entries addressed by an 'Unsigned' 8. Async (combinational) read
keeps the kernel pure and latency-free; on this Altera part it synthesises to
LUT/distributed logic, and the decode's 18 per-LED lookups replicate it (fine on
this device — observe it in the @quartus_map@ report).
-}
gammaLUT :: Unsigned 8 -> Unsigned DutyW
gammaLUT = asyncRomPow2 gammaTable

{- | Re-map a linear duty through the gamma ROM, indexing by its __top 8 bits__
(the intensity, quantised to 256 levels — ample). Note the edge: any duty in
@[65280, 65535]@ indexes entry 255 and so rounds /up/ to @maxBound@; that is
harmless only because the triangle steps down by @maxBound/kernelWidth@ per unit
distance and never emits a value inside that top bucket (it jumps @maxBound →
~65193@). So @gammaCorrect d <= d@ in practice, equal only at full scale.
-}
gammaCorrect :: Unsigned DutyW -> Unsigned DutyW
gammaCorrect d = gammaLUT (resize (d `shiftR` 8))

{- | The gamma falloff: the linear triangle, re-mapped through the gamma curve.
Shares the triangle's support and peak (so the bump is the same width and just as
bright at its centre) but darkens the mid-tones — the whole point. A pure
@distance → duty@ shape, like 'triangleKernel', so the decode treats them
interchangeably.
-}
gammaKernel :: Position -> Unsigned DutyW
gammaKernel = gammaCorrect . triangleKernel
