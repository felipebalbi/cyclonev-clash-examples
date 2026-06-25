{- |
PWM pattern generator on the C5G, built with the __Mealy__ construction.

@SW0@ selects which pattern drives the LED's brightness: low picks the steady
'Constant' duty, high picks the "breathing" 'Triangle'. Both patterns are clocked
by 'runMealy' (Clash's 'Clash.Prelude.mealyS', the @State@-monad form); the
sibling "PwmMoore" is identical but for swapping 'runMealy' → 'runMoore'. The
equivalence test proves the two produce the same waveform.

Like @blinky@/@pwm@ there is no reset port: the registers rely on their Cyclone V
power-up @init@ value, so 'topEntity' hands Clash a permanently de-asserted reset.
-}
module PwmMealy where

import Clash.Annotations.TH
import Clash.Prelude
import PwmCore (pwm)
import PwmPattern.Domain (Dom50)
import PwmPattern.Pattern (PrescaleExp, initial, prescale, runMealy)
import PwmPattern.Pattern.Constant (Constant)
import PwmPattern.Pattern.Triangle (Triangle)

{- | Synthesis entry point. The @"clk"@/@"sw"@/@"led"@ named-port annotations
(plus 'makeTopEntity') fix the Verilog port names that @pwm-pattern.tcl@ binds to
pins. The actual circuit is 'patternLed'; 'withClockResetEnable' supplies it the
hidden clock/reset/enable that 'pwm', 'prescale' and 'runMealy' need.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | SW0 pattern select (C5G SW[0], pin AC9): low = Constant, high = Triangle
        "sw" ::: Signal Dom50 Bit ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk sw = withClockResetEnable clk noReset enableGen (patternLed sw)
    where
        -- No user-reset pin: tie reset permanently de-asserted so the registers
        -- start from their power-up @init@ and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

{- | The full circuit, carrying the 'HiddenClockResetEnable' constraint so its
'where' bindings can use the clocked primitives ('topEntity' applies it under
'withClockResetEnable', which discharges that constraint).

Both patterns run in parallel; @SW0@ just 'mux'es which duty reaches the core. The
duty 'shadowDuty' inside 'pwm' makes the switch flip glitch-free — a mid-period
change is deferred to the next period boundary.
-}
patternLed :: (HiddenClockResetEnable dom) => Signal dom Bit -> Signal dom Bit
patternLed sw = led
    where
        (led, eop) = pwm dutySel
        -- Slow the ~763 Hz end-of-period tick to the pattern-advance rate.
        tick = prescale (SNat @PrescaleExp) eop
        dutyConst = runMealy (initial :: Constant) tick
        dutyTri = runMealy (initial :: Triangle) tick
        -- SW0 high -> Triangle, low -> Constant.
        dutySel = mux (bitToBool <$> sw) dutyTri dutyConst

makeTopEntity 'topEntity
