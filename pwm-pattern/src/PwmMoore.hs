module PwmMoore where

import Clash.Annotations.TH
import Clash.Prelude
import PwmCore (pwm)
import PwmPattern.Domain (Dom50)

type CounterWidth = 16

duty :: Unsigned CounterWidth
duty = (maxBound `div` 4) * 3

topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk = withClockResetEnable clk noReset enableGen (fst (pwm (pure duty)))
    where
        -- No user-reset pin: tie reset permanently de-asserted so the counter
        -- relies on its power-up @init@ value (Cyclone V configures registers
        -- from the bitstream) and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

makeTopEntity 'topEntity
