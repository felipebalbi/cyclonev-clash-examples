{- |
The wave's animation layer: /where/ the bump is, and /how bright/ each LED near
it glows.

Two pieces, deliberately kept apart — the __two triangles__:

  * the __bounce trajectory__ — 'Wave', a Moore machine whose position
    ping-pongs @0 → posMax → 0@ (pwm-pattern's 'Triangle' motion, retargeted from
    a brightness /level/ to a /position/);
  * the __glow shape__ — 'triangleKernel', a pure @distance → brightness@ falloff.

Both happen to be triangles, but they are unrelated: one moves the bump, the
other shapes its halo. The spatial decode that ties them together (turn one
position into a 'Vec' of per-LED duties) lives alongside, and the whole thing is
clocked one step at a time by the prescaled end-of-period tick.

All widths here (resolution 'PosF', step 'posStep', 'kernelWidth', the prescale)
are hardware-tunable by eye; the tests pin /shape/, not the exact numbers.
-}
module PwmWave.Wave where

import Clash.Prelude

{- | Position-advance prescale exponent: the bump steps once every
@2 ^ PrescaleExp@ end-of-period ticks. 'PwmWave.Core.pwmVec' hands up a free
~763 Hz time base; dividing it by @2 ^ PrescaleExp@ sets the bounce speed. At
@PrescaleExp = 0@ (÷1) with @PosF = 7@'s @2 * posMax = 2304@-step bounce that
lands a full sweep at ≈ 3 s. Raise it to slow the wave down. Only the /advance/
is gated; the PWM carrier always runs full-speed, so the LEDs never flicker.
-}
type PrescaleExp = 0

-- | Carrier/duty resolution: 16-bit -> the same ~763 Hz carrier as pwm/pwm-pattern.
type DutyW = 16

-- | Fixed-point position exponent: 2^PosF position units per LED (sub-LED glide).
type PosF = 7 -- tunable (smoothness vs. speed)

{- | A sub-LED position in fixed point. Width holds 0 .. (redLEDs-1)*2^PosF with
headroom for @|a - b|@ distance arithmetic.
-}
type Position = Unsigned 16

-- | Which way the bump is currently sweeping.
data Dir = Up | Down
        deriving (Generic, NFDataX, Eq, Show)

{- | The position machine's state: the sweep direction and the bump's current
(sub-LED) position. 'NFDataX' is load-bearing — 'moore' stores this in a register.
-}
data Wave = Wave Dir Position
        deriving (Generic, NFDataX, Eq, Show)

-- | One LED's worth of position (2 ^ PosF units).
ledUnit :: Position
ledUnit = bit (natToNum @PosF) -- = 128 at PosF = 7

-- | Red's far end: the peak walks 0 .. (10-1)*ledUnit, i.e. LED 0 .. LED 9.
posMax :: Position
posMax = 9 * ledUnit -- 9 = redLEDs - 1

-- | The near end of the sweep (LED 0). Named for symmetry with 'posMax'.
posMin :: Position
posMin = 0

{- | Position advance per tick. Must divide posMax so the bounce lands exactly on
0 and posMax (with PosF as the resolution knob, 1 stays plenty smooth).
-}
posStep :: Position
posStep = 1 -- tunable

-- | Bump half-width: how far the glow reaches from the peak (~1.5 LEDs).
kernelWidth :: Position
kernelWidth = 3 * ledUnit `div` 2 -- tunable (sharp dot .. soft blob)

{- | Divide a one-cycle tick by @2 ^ e@: emit a pulse once every @2 ^ e@ input
pulses. 'regEn' is enabled by @tickIn@, so @cnt@ counts /ticks/, not clock cycles
— it rolls @0 .. 2^e - 1@ over successive ticks and fires when one lands on
@cnt == 0@. Verbatim from pwm-pattern; the @SNat e@ pins @cnt@'s width.
-}
prescale ::
        forall e dom.
        (HiddenClockResetEnable dom, KnownNat e) =>
        SNat e -> Signal dom Bool -> Signal dom Bool
prescale SNat tickIn = tickIn .&&. (cnt .==. 0)
    where
        cnt :: Signal dom (Unsigned e)
        cnt = regEn 0 tickIn (cnt + 1)

-- | Power-up seed: at the near end (LED 0), about to sweep up.
initialWave :: Wave
initialWave = Wave Up 0

{- | Advance the bump one 'posStep' in the current direction, reversing one step
/past/ each endpoint so the extreme (0 or posMax) is visited exactly once — a
clean symmetric bounce, exactly pwm-pattern's 'Triangle' turnaround but in
position space. Every branch drives the position with a real value (never a bare
@x@ self-hold), so the register has a genuine data path and Quartus infers a
flip-flop, not a latch.
-}
waveNext :: Wave -> Wave
waveNext (Wave Up x)
        | x == posMax = Wave Down (x - posStep)
        | otherwise = Wave Up (x + posStep)
waveNext (Wave Down x)
        | x == posMin = Wave Up (x + posStep)
        | otherwise = Wave Down (x - posStep)

-- | Decode the state to the bump's position (the output the decode consumes).
wavePos :: Wave -> Position
wavePos (Wave _ p) = p

{- | Clock the bounce with 'moore': advance with 'waveNext' on a tick, hold
otherwise; 'wavePos' is the output decoder. Same shape as pwm-pattern's
@runMoore@ — the @Bool@ input is the prescaled "advance this tick?" pulse.
-}
runWave :: (HiddenClockResetEnable dom) => Signal dom Bool -> Signal dom Position
runWave = moore (\s adv -> if adv then waveNext s else s) wavePos initialWave

{- | The brightness falloff: full at the peak, fading linearly to dark at
'kernelWidth'. A pure @distance → duty@ shape (the /glow/ triangle), swappable
for a gamma curve later; the decode feeds it @|i*ledUnit - pos|@ per lane.

The clamp does double duty: it zeroes everything from 'kernelWidth' outward /and/
keeps @kernelWidth - d@ from underflowing the 'Unsigned' subtraction. The ramp is
widened to 'Unsigned' 32 before multiplying because the same-width product
@maxBound * (kernelWidth - d)@ overflows 16 bits (and wraps to garbage); widening
keeps it exact, so @d = 0@ yields precisely 'maxBound'.
-}
triangleKernel :: Position -> Unsigned DutyW
triangleKernel d
        | d >= kernelWidth = 0
        | otherwise = resize (full * rise `div` width)
    where
        full = resize (maxBound :: Unsigned DutyW) :: Unsigned 32
        rise = resize (kernelWidth - d) :: Unsigned 32
        width = resize kernelWidth :: Unsigned 32

{- | The spatial decode: render the bump centred at @pos@ across @n@ LEDs. 'imap'
walks the lanes; lane @i@ sits at fixed-point location @i * ledUnit@, so its
brightness is 'triangleKernel' of its distance to the peak. This is where the two
triangles meet — the position (from 'runWave') picks /where/, the kernel decides
/how bright/. Polymorphic in @n@ so the same decode serves both banks.
-}
bumpVec :: forall n. (KnownNat n) => Position -> Vec n (Unsigned DutyW)
bumpVec pos = imap (\i _ -> triangleKernel (ledDist i pos)) (repeat ())

{- | Distance from LED @i@'s centre (@i * ledUnit@) to a position. Branches on
order rather than @abs (here - pos)@ because 'Position' is 'Unsigned': @abs@ is a
no-op there and the subtraction would wrap below zero, so the magnitude is taken
explicitly.
-}
ledDist :: (Integral a) => a -> Position -> Position
ledDist i pos = if here >= pos then here - pos else pos - here
    where
        here = fromIntegral i * ledUnit

-- | Red bank: the bump straight off the decode, peak walking with @pos@ (LED 0..9).
redDuties :: Position -> Vec 10 (Unsigned DutyW)
redDuties = bumpVec

{- | Green bank: red's bump /reversed/. That single 'reverse' is the
counter-rotation — green lane @i@ shows red-style lane @7 - i@, so as red sweeps
@0 → 9@ green sweeps @7 → 0@, the banks moving in opposite directions.
-}
greenDuties :: Position -> Vec 8 (Unsigned DutyW)
greenDuties = reverse . bumpVec
