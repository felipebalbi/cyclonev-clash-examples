{- |
Pattern-generator type classes for the pwm-pattern example.

A /pattern generator/ is a small state machine that produces a time-varying duty
cycle to feed @PwmCore.pwm@ — a ramp that "breathes", a steady level, a sweep,
and so on. This module defines the /contracts/; the concrete patterns
(@Constant@, @Triangle@, …) live under @PwmPattern.Pattern.*@, and the drivers
that actually clock them (@runMoore@, @runMealy@) are added alongside these
classes.

== Two spellings of the same machine

The point of this example is to build the same generator two ways:

  * the __Moore__ spelling — a pure transition 'next' and a pure output decoder
    'duty', clocked by 'moore';
  * the __Mealy__ spelling — a single 'step' action in the strict 'State' monad,
    clocked by 'mealyS'.

So each pattern type carries /both/ a 'PatGenMoore' and a 'PatGenMealy' instance,
genuinely re-authored, while the shared 'PatGen' base holds what both need. A
property test later asserts the two spellings produce bit-identical waveforms.
-}
module PwmPattern.Pattern where

import Clash.Prelude
import Control.Monad.State.Strict (State)

{- | Duty-cycle resolution shared by every pattern and the PWM core: a 16-bit
duty drives the same @50e6 / 2^16 ≈ 763 Hz@ carrier as the @pwm@ example. It is a
fixed 'type' rather than a per-pattern associated type family because all
patterns feed the one PWM, so a per-type width would buy nothing.
-}
type DutyW = 16

{- | Pattern-advance prescale exponent: the generators step once every
@2 ^ PrescaleExp@ end-of-period ticks. The PWM core's end-of-period pulse is a
free ~763 Hz time base; dividing it by @2 ^ 2 = 4@ — with Triangle's 256-level
sweep — lands a full "breathe" at ≈ 2.7 s. Raise it for slower animations. Only
the /advance/ is slowed; the PWM carrier always runs at full clock speed, so the
LED never flickers.
-}
type PrescaleExp = 2

{- | What every pattern shares, independent of how it is clocked.

The 'NFDataX' superclass is load-bearing: a pattern's state is held in a register
by 'moore' / 'mealyS', and Clash requires 'NFDataX' for anything register-stored.
Putting it here makes every pattern register-storable by construction and keeps
the driver signatures clean (a @PatGenMoore a@ already implies @NFDataX a@).
-}
class (NFDataX a) => PatGen a where
        {- | Power-up / seed state. A top names a pattern's seed by type, e.g.
        @runMoore (initial :: Constant) tick@ — which is also why the seed lives
        on this base class rather than being threaded around as an argument.
        -}
        initial :: a

{- | The __Moore__ spelling: two pure functions that 'moore' consumes. The output
('duty') depends only on the current state, never on the input.
-}
class (PatGen a) => PatGenMoore a where
        -- | Advance the state by one tick.
        next :: a -> a

        -- | Decode the current state to a brightness (out of @2 ^ DutyW@).
        duty :: a -> Unsigned DutyW

{- | The __Mealy__ spelling: one action in the strict 'State' monad, clocked by
'mealyS' (whose transfer function has the shape @i -> 'State' s o@).

The 'Bool' argument is that @i@ — "advance this tick?" — which the driver feeds
from the prescaled pattern-advance tick. An instance reads the state, /conditionally/
'Control.Monad.State.Strict.put's the transition (only when told to advance), and
returns the duty of the __pre-update__ state. Emitting the pre-update value is
what keeps @runMealy@ bit-identical to @runMoore@; returning the post-update duty
would shift the whole waveform by one cycle.
-}
class (PatGen a) => PatGenMealy a where
        -- | Given "advance this tick?", update the state and yield the current duty.
        step :: Bool -> State a (Unsigned DutyW)

{- | Drive a pattern with Clash's 'moore'. The transfer function advances with
'next' on a tick and otherwise holds the state; 'duty' is the output decoder.
Point-free: 'moore' takes @transfer@, @decoder@, the seed, and the input signal,
so supplying the first two leaves @seed -> tick -> duty@ — exactly this signature.
Each cycle's output is 'duty' of the /current/ state (the defining Moore shape).
-}
runMoore ::
        (HiddenClockResetEnable dom, PatGenMoore a) =>
        a -> Signal dom Bool -> Signal dom (Unsigned DutyW)
runMoore = moore transfer duty
    where
        transfer = \s adv -> if adv then next s else s

{- | Drive a pattern with 'mealyS' — where the 'State' spelling pays off. 'mealyS'
wants a transfer function of shape @i -> State s o@, and 'step' already /is/ that
shape, so it slots in with no glue. Deliberately the same type as 'runMoore': the
two tops differ only by which of these they call, and the equivalence test pits
them against each other directly.
-}
runMealy ::
        (HiddenClockResetEnable dom, PatGenMealy a) =>
        a -> Signal dom Bool -> Signal dom (Unsigned DutyW)
runMealy = mealyS step

{- | Divide a one-cycle tick by @2 ^ e@: emit a pulse once every @2 ^ e@ input
pulses. The crux is that 'regEn' is enabled by @tickIn@, so @cnt@ counts /ticks/,
not clock cycles — it rolls @0 .. 2^e - 1@ over successive ticks, and the output
fires when a tick lands on @cnt == 0@. (A plain 'register' would count every cycle
and divide the wrong thing.) The @SNat e@ argument pins @cnt@'s width.
-}
prescale ::
        forall e dom.
        (HiddenClockResetEnable dom, KnownNat e) =>
        SNat e -> Signal dom Bool -> Signal dom Bool
prescale SNat tickIn = tickIn .&&. (cnt .==. 0)
    where
        cnt :: Signal dom (Unsigned e)
        cnt = regEn 0 tickIn (cnt + 1)
