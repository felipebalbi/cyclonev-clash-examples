module SevenSeg where

import Clash.Annotations.TH
import Clash.Prelude

import SevenSeg.Decode (displayPorts)
import SevenSeg.Domain (Dom50)
import SevenSeg.Odometer (odometer)

{- | The four digit buses, MSD on @hex3@. Carries 'HiddenClockResetEnable' so its
'where' bindings can use the clocked 'odometer'; 'topEntity' discharges the
constraint via 'withClockResetEnable'. 'displayPorts' yields the four buses in
port order (index 0 = @hex0@), which 'unbundle' + the 'Vec' pattern split into
the named outputs.
-}
displays ::
        forall dom.
        (HiddenClockResetEnable dom) =>
        ( Signal dom (BitVector 7)
        , Signal dom (BitVector 7)
        , Signal dom (BitVector 7)
        , Signal dom (BitVector 7)
        )
displays = (busAt 0, busAt 1, busAt 2, busAt 3)
    where
        ports = unbundle (displayPorts <$> odometer)
        busAt :: Index 4 -> Signal dom (BitVector 7)
        busAt i = ports !! i

{- | Synthesis entry point. The @"clk"@/@"hex0".."hex3"@ named-port annotations
(plus 'makeTopEntity') fix the Verilog port names that @sevenseg.tcl@ binds to
pins; each 'BitVector' 7 renders as a packed @hex_i[6:0]@ bus (active-low).

Like the siblings there is no reset port: the registers rely on their Cyclone V
power-up @init@, so 'topEntity' hands Clash a permanently de-asserted reset and
Clash emits no @reset@ port.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        ( -- \| Digit 0, rightmost (C5G HEX0[6:0], active-low)
          "hex0" ::: Signal Dom50 (BitVector 7)
        , -- \| Digit 1 (C5G HEX1[6:0], active-low)
          "hex1" ::: Signal Dom50 (BitVector 7)
        , -- \| Digit 2 (C5G HEX2[6:0], active-low)
          "hex2" ::: Signal Dom50 (BitVector 7)
        , -- \| Digit 3, leftmost / MSD (C5G HEX3[6:0], active-low)
          "hex3" ::: Signal Dom50 (BitVector 7)
        )
topEntity clk = withClockResetEnable clk noReset enableGen displays
    where
        -- No user-reset pin: tie reset permanently de-asserted so the registers
        -- start from their power-up @init@ and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

makeTopEntity 'topEntity
