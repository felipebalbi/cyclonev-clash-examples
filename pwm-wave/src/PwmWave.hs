module PwmWave where

import Clash.Annotations.TH
import Clash.Prelude
import PwmWave.Core
import PwmWave.Domain (Dom50)
import PwmWave.Wave

{- | The full circuit, carrying the 'HiddenClockResetEnable' constraint so its
'where' bindings can use the clocked primitives ('runWave', 'prescale',
'pwmVec'). 'topEntity' applies it under 'withClockResetEnable', which discharges
the constraint — keeping the logic in /this/ binding (rather than a flat 'where'
on 'topEntity') is what puts those primitives in reach of the hidden clock.

The pipeline: 'runWave' ping-pongs the bump position (advanced by the prescaled
end-of-period tick), the spatial decode turns it into red and green duty vectors,
and __one__ 'pwmVec' renders both banks — the two duty vectors are concatenated
into a @Vec 18@ so a single carrier drives all 18 LEDs, then 'splitAtI' splits the
LED bits back into the @10@ + @8@ banks.
-}
waveLeds :: (HiddenClockResetEnable dom) => (Signal dom (Vec 10 Bit), Signal dom (Vec 8 Bit))
waveLeds = (ledr, ledg)
    where
        pos = runWave tick
        tick = prescale (SNat @PrescaleExp) eop
        dutyR = redDuties <$> pos
        dutyG = greenDuties <$> pos
        (leds18, eop) = pwmVec ((++) <$> dutyR <*> dutyG)
        (ledr, ledg) = unbundle (splitAtI <$> leds18)

{- | Synthesis entry point. The @"clk"@/@"ledr"@/@"ledg"@ named-port annotations
(plus 'makeTopEntity') fix the Verilog port names that @pwm-wave.tcl@ binds to
pins; the @Vec n Bit@ outputs render as packed @ledr[9:0]@/@ledg[7:0]@ buses. The
actual circuit is 'waveLeds'; 'withClockResetEnable' supplies the hidden
clock/reset/enable it needs.

Like @blinky@/@pwm@/@pwm-pattern@ there is no reset port: the registers rely on
their Cyclone V power-up @init@, so 'topEntity' hands Clash a permanently
de-asserted reset and Clash emits no @reset@ port.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        ( -- | Red bank, LED 0..9 (C5G LEDR[9:0])
          "ledr" ::: Signal Dom50 (Vec 10 Bit)
        , -- | Green bank, LED 0..7 (C5G LEDG[7:0])
          "ledg" ::: Signal Dom50 (Vec 8 Bit)
        )
topEntity clk = withClockResetEnable clk noReset enableGen waveLeds
    where
        -- No user-reset pin: tie reset permanently de-asserted so the registers
        -- start from their power-up @init@ and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

makeTopEntity 'topEntity
