{- |
The odometer's time base: one free-running wide counter whose __high 16 bits__
are the visible value. Taking the high bits is a divider — the same "a counter's
high bits are a slower count" idea as @blinky@ — so @HEX0@ (the low nibble) spins
fastest and each digit to its left advances 16× slower.

'odometerValue' is the pure high-slice (unit-tested without sampling);
'odometer' is its clocked wrapper.
-}
module SevenSeg.Odometer where

import Clash.Prelude

{- | Visible-rate divider exponent: the value advances at @50e6 / 2^DivBits@.
By-eye tunable like @blinky@'s divider; @23@ → ≈ 6 Hz (HEX0 visibly spins, HEX1
ticks ~0.4 Hz). The wide counter is then @16 + DivBits = 39@ bits.
-}
type DivBits = 23

{- | The visible 16-bit word: the high 16 bits of a @(16 + k)@-bit counter.
Polymorphic in @k@ so tests can pick a small one; 'odometer' instantiates
@k = DivBits@. Pinned by 'Tests.Odometer' to equal @resize (counter \`shiftR\` k)@.
-}
odometerValue :: forall k. (KnownNat k) => Unsigned (16 + k) -> Unsigned 16
odometerValue v = resize (v `shiftR` natToNum @k)

{- | The clocked odometer: a free-running @(16 + DivBits)@-bit counter, sliced to
its visible high 16 bits. No reset — relies on the Cyclone V power-up @init@.
-}
odometer :: (HiddenClockResetEnable dom) => Signal dom (Unsigned 16)
odometer = odometerValue @DivBits <$> counter
    where
        counter = register 0 (counter + 1)
