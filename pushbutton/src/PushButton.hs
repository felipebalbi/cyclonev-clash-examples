{- |
Pushbutton-toggled LED for the C5G: pressing KEY0 flips @LEDR[0]@, which then
holds until the next press.

The datapath is the three 'PushButton.Button' primitives in series — a 2-FF
input __synchronizer__, a rising-edge __detector__, and a __toggle__ flip-flop —
fronted by the active-low→@pressed@ polarity flip:

@
key0 (async, active-low, RC-debounced)
  │  'synchronize'   2-FF metastability hardener
  ▼
  │  invert          active-low pin → @pressed = True@   (a press is a /falling/ edge of the pin)
  ▼
pressed
  │  'risingEdge'    one-cycle pulse per new press
  ▼
  │  'toggleOn'      T flip-flop, seeded low
  ▼
led → LEDR[0]
@

Like the @blinky@ \/ @sevenseg@ siblings there is __no reset port__: the toggle
flip-flop powers up 'low' from the Cyclone V @init@ value, so 'topEntity' hands
Clash a permanently de-asserted reset and Clash emits no @reset@ port. If you ever
want a clear button, synchronize a /separate/ KEY into a 'Reset' the way
@BlinkyWithReset@ does — don't drive the LED through a raw reset net.
-}
module PushButton where

import Clash.Annotations.TH
import Clash.Prelude

import PushButton.Button (risingEdge, synchronize, toggleOn)
import PushButton.Domain (Dom50)

{- | The clocked toggle datapath: raw active-low KEY0 'Bit' in, LED 'Bit' out.

Carries 'HiddenClockResetEnable' so it can use the clocked primitives;
'topEntity' discharges the constraint via 'withClockResetEnable' (a flat @where@
on 'topEntity' would fail with "unbound implicit parameters" — the @sevenseg@
'SevenSeg.displays' precedent).

The pipeline: 'synchronize' the pin, flip active-low→@pressed@, 'risingEdge'-detect
the press, and feed that pulse to 'toggleOn'. 'Tests.Button' (the capstone) pins
"one toggle per /new/ press, held presses ignored".
-}
toggleLed :: (HiddenClockResetEnable dom) => Signal dom Bit -> Signal dom Bit
toggleLed = toggleOn . risingEdge . fmap (== low) . synchronize

{- | Synthesis entry point. The @"clk"@ \/ @"key0"@ \/ @"led"@ named-port
annotations (plus 'makeTopEntity') fix the Verilog port names that
@pushbutton.tcl@ binds to pins.

No reset port: 'topEntity' passes a permanently de-asserted reset
('unsafeFromActiveHigh' '(pure' 'False)') so the toggle flip-flop starts from its
power-up @init@ and Clash emits no @reset@ port — exactly like @sevenseg@.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | On-board push button KEY0, active-low (C5G pin P11)
        "key0" ::: Signal Dom50 Bit ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk key0 = withClockResetEnable clk noReset enableGen (toggleLed key0)
    where
        -- No user-reset pin: tie reset permanently de-asserted so the toggle FF
        -- starts from its power-up @init@ and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

makeTopEntity 'topEntity
