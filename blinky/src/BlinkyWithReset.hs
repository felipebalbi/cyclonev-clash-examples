{- |
Blinking LED for the C5G, but reset from the on-board push button KEY0.

Same divider as "Blinky" (it reuses 'Blinky.blink' and 'Blinky.CounterWidth'
unchanged); the only difference is that the counter is now held in reset while
KEY0 is pressed, instead of relying solely on the power-up @init@ value.
Releasing the button restarts the blink from 0.

== Why this needs a synchronizer (the whole point of this variant)

The C5G's user buttons (@KEY[3:0]@, KEY0 on pin P11) are __active-low__ —
released is high, pressing pulls it low — and they are __asynchronous__ to the
50 MHz clock and mechanically bouncy. Feeding such a signal straight into
register resets is unsafe: if the de-assert (release) lands too close to a clock
edge a register can go metastable, and different registers may leave reset on
different cycles. (The C5G factory demo resets on @negedge KEY[0]@ for the same
reason.)

The fix is the classic __asynchronous-assert / synchronous-deassert__ scheme:
assert reset immediately (so even a glitch is safe), but only release it after
the clean edge has been clocked through two flip-flops. 'resetSynchronizer' is
exactly that 2-FF reset synchronizer; because 'Blinky.Domain.Dom50' is an
asynchronous-reset domain, it gives async-assert with a 2-FF synchronous
release for free.

== Reset construction, read as a pipeline

@
unsafeFromActiveLow  -- "this Bool is an active-low reset" (asserted when low)
        |               — \"unsafe\" precisely because it is not yet synchronized
resetSynchronizer clk -- the 2-FF synchronizer that makes the release safe
@

No debounce is needed: for a /reset/, a bouncing release just re-extends the
reset pulse harmlessly (unlike a button that increments something).
-}
module BlinkyWithReset where

import Blinky (CounterWidth, blink)
import Blinky.Domain (Dom50)
import Clash.Annotations.TH
import Clash.Prelude

{- | Synthesis entry point. The @"clk" :::@ / @"rst" :::@ / @"led" :::@
named-port annotations (plus 'makeTopEntity' below) fix the generated Verilog
port names so @blinky.tcl@ binds them to the right pins. The @rst@ port is the
raw active-low KEY0 pin; the actual 'Reset' is built from it below.
-}
topEntity ::
        -- | 50 MHz board clock (C5G CLOCK_50_B5B, pin R20)
        "clk" ::: Clock Dom50 ->
        -- | On-board push button KEY0, active-low (C5G pin P11); drives reset
        "rst" ::: Signal Dom50 Bit ->
        -- | On-board red LED (C5G LEDR[0], pin F7)
        "led" ::: Signal Dom50 Bit
topEntity clk rstPin = withClockResetEnable clk rst enableGen (blink (SNat @CounterWidth))
    where
        -- Active-low button -> Reset (still unsafe: not aligned to clk) -> run
        -- the release through the 2-FF synchronizer so registers leave reset
        -- cleanly on the same cycle.
        rst = resetSynchronizer clk (unsafeFromActiveLow (bitToBool <$> rstPin))

makeTopEntity 'topEntity
