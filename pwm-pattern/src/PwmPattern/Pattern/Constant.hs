{- |
The simplest pattern generator: a __constant__ duty.

Reproduces the @pwm@ example's fixed-brightness behaviour, now expressed through
the 'PatGen' framework — which makes it the natural sanity anchor for the whole
example: @runMoore (initial :: Constant)@ behaves exactly like the old
constant-duty @pwm@. It is also the floor case for the two spellings: the state
never changes, so 'next' is the identity and 'step' yields the duty unchanged.

== Why the state carries no value

An earlier version made @Constant@ carry the duty as a field so a top could pick
the level via @Constant n@. That stored the level in the 'moore' / 'mealyS' state
register — and because these tops have no reset (Cyclone V power-up @init@ only),
the @mealyS@ register became a bare self-hold (@x1_0 <= x1_0@) that Quartus
infers as a __latch__, losing the value on hardware. A constant has no real
state, so the honest fix is a state-less @Constant@ whose duty is a wired literal
('constDuty') — exactly like @pwm@. Change the brightness by editing 'constDuty'.
-}
module PwmPattern.Pattern.Constant where

import Clash.Prelude
import PwmPattern.Pattern (DutyW, PatGen (..), PatGenMealy (..), PatGenMoore (..))

-- | A constant-duty generator. State-less: its single value carries no data, so
-- the duty is a wired literal ('constDuty') rather than a register.
data Constant = Constant
        deriving (Generic, NFDataX, Eq, Show)

{- | The fixed level: @(maxBound \`div\` 4) * 3@ — three-quarters of full scale,
identical to the @pwm@ example's fixed duty.
-}
constDuty :: Unsigned DutyW
constDuty = (maxBound `div` 4) * 3

instance PatGen Constant where
        initial = Constant

instance PatGenMoore Constant where
        -- A constant has nowhere to go, and always decodes to the same level.
        next = id
        duty _ = constDuty

instance PatGenMealy Constant where
        -- The Mealy spelling: ignore the advance tick, never touch the (empty)
        -- state, and yield the fixed level. 'pure' performs no 'put', so there is
        -- no self-holding state register to be latched (contrast Triangle's 'step',
        -- which evolves real state).
        step _ = pure constDuty
