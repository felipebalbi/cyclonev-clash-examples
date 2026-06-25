{- |
A triangle-wave ("breathing") pattern generator.

Where 'PwmPattern.Pattern.Constant.Constant' has no state, @Triangle@ has real
state — a /level/ that ramps up and down, plus the /direction/ it is currently
moving — which is what makes it worth building two ways. The level rises
@0 .. maxBound@, reverses, falls back to @0@, reverses again, forever; fed
through PWM this dims the LED smoothly in and out.

== Why the level is narrow ('LevelW' < 'DutyW')

The animation runs in an 8-bit level space but the PWM wants a 16-bit duty, and
that gap is deliberate: it sets the breathe /rate/. A full up+down sweep is
@2 * 2^8 = 512@ steps; at the prescaled end-of-period tick (~191 Hz) that lands a
breathe at ≈ 2.7 s. A 16-bit level would take ~86 s per sweep — invisibly slow.
'scaleToDuty' bridges the two by left-justifying the level into the duty.

== Two spellings

'PatGenMoore' gives the pure @next@/@duty@ pair; 'PatGenMealy' re-authors the
/same/ turnaround inside a 'Control.Monad.State.Strict.State' action. They must
agree cycle-for-cycle — the equivalence test is what enforces it.
-}
module PwmPattern.Pattern.Triangle where

import Clash.Prelude
import Control.Monad (when)
import Control.Monad.State.Strict (get, put)
import PwmPattern.Pattern (DutyW, PatGen (..), PatGenMealy (..), PatGenMoore (..))

-- | Width of the ramp /level/ — the animation resolution. Kept below 'DutyW' so a
-- full sweep is short enough to see (see the module header). 8 bits → 256 levels.
type LevelW = 8

-- | Which way the level is currently moving.
data Dir = Up | Down
        deriving (Generic, NFDataX, Eq, Show)

{- | The generator state: the current direction and level. Both are needed —
the level decodes to a brightness, and the direction decides when to reverse.
-}
data Triangle = Triangle Dir (Unsigned LevelW)
        deriving (Generic, NFDataX, Eq, Show)

{- | Widen an 8-bit level to a 16-bit duty by left-justifying it: append
@DutyW - LevelW@ zero bits below it (the typelits plugins compute @16 - 8 = 8@).
So level @0 .. 255@ maps to duty @0, 256, .., 65280@ — the level scaled up to the
full PWM range, brightest at the top. Shared by both spellings: it is a pure
decode, not part of either construction's transition logic.
-}
scaleToDuty :: Unsigned LevelW -> Unsigned DutyW
scaleToDuty lvl = unpack (pack lvl ++# (0 :: BitVector (DutyW - LevelW)))

instance PatGen Triangle where
        initial = Triangle Up 0

instance PatGenMoore Triangle where
        -- Ramp in the current direction, reversing one step *past* each endpoint so
        -- the peak/trough is visited exactly once (a clean symmetric triangle).
        next (Triangle Up x)
                | x == maxBound = Triangle Down (x - 1) -- hit top, reverse
                | otherwise = Triangle Up (x + 1)
        next (Triangle Down x)
                | x == minBound = Triangle Up (x + 1) -- hit bottom, reverse
                | otherwise = Triangle Down (x - 1)

        duty (Triangle _ x) = scaleToDuty x

instance PatGenMealy Triangle where
        step advance = do
                Triangle dir x <- get
                -- The same turnaround as 'next', re-authored here so the Mealy
                -- spelling stands alone (a real design would pick one construction;
                -- the equivalence test guards that the two copies stay in step).
                let s' = case dir of
                        Up
                                | x == maxBound -> Triangle Down (x - 1) -- hit top, reverse
                                | otherwise -> Triangle Up (x + 1)
                        Down
                                | x == minBound -> Triangle Up (x + 1) -- hit bottom, reverse
                                | otherwise -> Triangle Down (x - 1)
                when advance (put s')
                pure (scaleToDuty x) -- pre-update level x, never x'
