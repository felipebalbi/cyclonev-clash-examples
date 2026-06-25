module PwmCore where

import Clash.Prelude

{- | The PWM core, polymorphic in the clock domain and counter width @n@. A
free-running counter is compared against @shadowDuty@ each cycle; the output is
high while the count is below the threshold. Keeping the @duty'@ input a 'Signal'
(rather than a fixed parameter) is what lets a ramp, the switches, or a pattern
generator drive the brightness later without touching this definition. The width
@n@ is fixed by the @duty'@ argument's type, so — unlike blinky's @blink@ — no
'SNat' is needed.

One important note here: why @shadowDuty@

Ultimately, we want a glitch-free transition from one duty value to another. The
way to achieve that is by changing duty exactly when the counter register wraps
around. The obvious solution is to compare the counter against its maximum value
(that's where @maxBound@ comes in) and use that to force a new duty value to be
latched in the @shadowDuty@ register.
-}
pwm ::
        forall dom n.
        (HiddenClockResetEnable dom, KnownNat n, 1 <= n) =>
        -- | Duty cycle (out of @2^n@)
        Signal dom (Unsigned n) ->
        -- | Led: high while the counter is below the duty
        (Signal dom Bit, Signal dom Bool) -- (led, end-of-period)
pwm duty' = (led, endOfPeriod)
    where
        counter :: Signal dom (Unsigned n)
        counter = register 0 (counter + 1)
        led :: Signal dom Bit
        led = boolToBit <$> (counter .<. shadowDuty)
        endOfPeriod :: Signal dom Bool
        endOfPeriod = counter .==. maxBound
        shadowDuty :: Signal dom (Unsigned n)
        shadowDuty = regEn 0 endOfPeriod duty'
