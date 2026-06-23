{- |
Blinking LED for the Terasic Cyclone V GX Starter Kit (C5G).

A free-running counter divides the 50 MHz board clock; its most-significant bit
drives an on-board red LED (@LEDR[0]@, pin F7). This is the Quartus/Cyclone V
retarget of the iCEbreaker @Blinky@ from the sibling @icebreaker-clash-examples@
repo — only the clock frequency, counter width, and backend change.

== Why there is no reset port

Like the iCE40 original, we never generate a reset net: a Cyclone V register
comes up at its @init@ value (here 0) straight from the FPGA configuration
bitstream, so the divider starts cleanly without a dedicated reset pin. In Clash
that means handing 'topEntity' a permanently de-asserted reset
('unsafeFromActiveHigh' of a constant 'False'); Clash then sees the reset is
unused and emits no @reset@ port, leaving just @clk@ and @led@ for Quartus to
bind. (The C5G does have push-buttons, but wiring one as reset is out of scope
for this single-LED smoke test.)

== Shape vs. the iCEbreaker original

Identical circuit. The only deltas are 'Blinky.Domain.Dom50' (50 MHz instead of
12 MHz) and 'CounterWidth' (26 instead of 25), so the visible blink rate lands
in the same ~1 s ballpark on the faster clock.
-}
module Blinky where

import Blinky.Domain (Dom50)
import Clash.Annotations.TH
import Clash.Prelude

{- | Width of the divider counter. At 50 MHz, the MSB of a 26-bit counter (bit
25) toggles every @2 ^ 25 / 50e6 ≈ 0.67 s@, a ~1.34 s blink period — the same
bit the Terasic C5G factory demo uses (@Cont[25]@) for its LED sweep. The
synthesis top bakes in this width; the test sweeps a much smaller one so a full
period fits in a quick simulation.
-}
type CounterWidth = 26

{- | Synthesis entry point. The @"clk" :::@ / @"led" :::@ named-port
annotations (plus 'makeTopEntity' below) fix the generated Verilog port
names so @blinky.tcl@'s pin assignments bind to the right wires.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk = withClockResetEnable clk noReset enableGen (blink (SNat @CounterWidth))
    where
        -- No user-reset pin: tie reset permanently de-asserted so the counter
        -- relies on its power-up @init@ value (Cyclone V configures registers
        -- from the bitstream) and Clash emits no @reset@ port.
        noReset = unsafeFromActiveHigh (pure False)

{- | The actual circuit, polymorphic in both the clock domain and the counter
width. The width is passed as an 'SNat' so the same definition elaborates
for synthesis (@26@) and simulation (small) with no duplication.

@counter@ is defined recursively as @register 0 (counter + 1)@: 'register'
delays its argument by one cycle, so this is a free-running counter that
starts at 0, not an infinite loop.
-}
blink ::
        forall dom n.
        (HiddenClockResetEnable dom, KnownNat n, 1 <= n) =>
        -- | Counter width
        SNat n ->
        -- | LED output: the counter's most-significant bit
        Signal dom Bit
blink SNat = msb <$> counter
    where
        counter :: Signal dom (Unsigned n)
        counter = register 0 (counter + 1)

makeTopEntity 'topEntity
