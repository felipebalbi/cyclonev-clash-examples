{- |
PWM (pulse-width modulation) brightness control for the Terasic Cyclone V GX
Starter Kit (C5G).

The follow-on to blinky. Blinky drove the LED from the most-significant bit of a
free-running counter — a fixed 50% square wave. PWM keeps the same counter but
compares it against a /duty/ threshold: the output is high while the counter is
below @duty@ and low above it. The high fraction is @duty / 2^n@, so the LED's
average brightness tracks @duty@.

Here @duty@ is a compile-time constant, so the LED just sits at one brightness.
But 'pwm' takes the duty as a 'Signal', not a fixed parameter, so the very same
component will later accept a time-varying duty — a ramp to "breathe", @SW[9:0]@
to dim by hand, or a pattern generator — with no change to this code.

== Duty semantics

@counter .<. duty@ is high for @duty@ of every @2^n@ cycles:

  * @duty = 0@        -> always off (0%)
  * @duty = 2^n - 1@  -> on for all but one cycle of the period
  * fully on is unreachable with a plain @Unsigned n@ duty (the top count is
    never less than itself) — irrelevant for an LED.

== Why there is no reset port

Same as blinky: a Cyclone V register powers up at its @init@ value (0) from the
configuration bitstream, so the counter starts cleanly with no reset pin.
'topEntity' hands Clash a permanently de-asserted reset, so Clash emits no
@reset@ port — just @clk@ and @led@.
-}
module Pwm where

import Clash.Annotations.TH
import Clash.Prelude
import Pwm.Domain (Dom50)

{- | Counter width = duty resolution (@2^16 = 65536@ brightness steps). It also
fixes the PWM /frequency/: the counter wraps every @2^16@ clocks, so at 50 MHz
the LED is modulated at @50e6 / 2^16 ≈ 763 Hz@ — comfortably above the ~100 Hz
flicker threshold, so the eye integrates it into a steady brightness rather than
seeing it blink. A smaller width raises the frequency but coarsens the steps.
-}
type CounterWidth = 16

{- | Fixed duty for this demo: @(maxBound `div` 4) * 3@, i.e. three quarters of
full scale (~75% brightness). @maxBound :: Unsigned 16@ is @2^16 - 1@; a quarter
of that, times three, is the 75% point. 'topEntity' lifts it to a constant
'Signal' with 'pure' — replace it with a time-varying signal to dim or breathe.
-}
duty :: Unsigned CounterWidth
duty = (maxBound `div` 4) * 3

{- | Synthesis entry point. The @"clk" :::@ / @"led" :::@ named-port annotations
(plus 'makeTopEntity' below) fix the generated Verilog port names so @pwm.tcl@
binds them to the right pins. The constant 'duty' is lifted into a steady
'Signal' with @pure duty@, whose type also pins the counter width to
'CounterWidth'.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk = withClockResetEnable clk noReset enableGen (pwm (pure duty))
    where
        -- No user-reset pin: tie reset permanently de-asserted so the counter
        -- relies on its power-up @init@ value (Cyclone V configures registers
        -- from the bitstream) and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

{- | The PWM core, polymorphic in the clock domain and counter width @n@. A
free-running counter is compared against @duty@ each cycle; the output is high
while the count is below the threshold. Keeping @duty@ a 'Signal' (rather than a
fixed parameter) is what lets a ramp, the switches, or a pattern generator drive
the brightness later without touching this definition. The width @n@ is fixed by
the @duty@ argument's type, so — unlike blinky's @blink@ — no 'SNat' is needed.
-}
pwm ::
        forall dom n.
        (HiddenClockResetEnable dom, KnownNat n, 1 <= n) =>
        -- | Duty cycle (out of @2^n@)
        Signal dom (Unsigned n) ->
        -- | LED output: high while the counter is below the duty
        Signal dom Bit
pwm duty' = boolToBit <$> (counter .<. duty')
    where
        -- The output expression above: `counter .<. duty'` lifts `<` over the
        -- two signals to a `Signal dom Bool` (high while below the threshold),
        -- and `boolToBit <$>` maps each `Bool` to a `Bit` for the LED port.

        -- Free-running counter: 0, 1, .., 2^n - 1, wrapping. `register` delays
        -- its argument by one cycle, so this recursive `let` is a counter, not
        -- an infinite loop (the same idiom as blinky); it starts at power-up 0.
        counter :: Signal dom (Unsigned n)
        counter = register 0 (counter + 1)

makeTopEntity 'topEntity
