{- |
The three clocked primitives behind the pushbutton toggle, each a tiny synchronous
circuit in a single 'HiddenClockResetEnable' domain:

  * 'synchronize' — a 2-FF __metastability__ synchronizer for the async button pin.
  * 'risingEdge'  — a one-cycle pulse on every rising edge (the edge detector).
  * 'toggleOn'    — a T flip-flop that flips a stored bit on each pulse.

These recur all over the book: the UART receiver synchronizes its RX line and
edge-detects the start bit; a keypad scanner edge-detects each row. Building them
by hand here is the point — the Clash standard library ships equivalents
('Clash.Explicit.Synchronizer.dualFlipFlopSynchronizer', 'Clash.Prelude.isRising'
\/ 'Clash.Prelude.isFalling'), noted per function for later reference.

== Synchronize ≠ debounce

The C5G @KEY@ buttons are __RC-filtered in hardware__, so they don't bounce — but
they are still __asynchronous__ to 'PushButton.Domain.Dom50'. A clean-but-async
edge can still violate a flip-flop's setup\/hold and drive it metastable. The RC
filter solves bounce; 'synchronize' solves metastability. Both are real problems;
here the board owns the first so the gateware owns the second. Do not let "it's
already debounced" talk you out of the synchronizer.

Each primitive drives a real register value on every cycle (the
@register@\/@complement@ style), so Quartus infers flip-flops, not latches.
-}
module PushButton.Button (
        synchronize,
        risingEdge,
        toggleOn,
) where

import Clash.Prelude

{- | Two-flip-flop input synchronizer: pass an asynchronous 'Bit' through two
cascaded 'register's so a metastable sample has a full clock period to settle
before any logic reads it.

__Law__ (pinned by 'Tests.Button'): the output is the input delayed by exactly
__two__ cycles. After the initial warm-up the stream is otherwise unchanged — a
pure 2-cycle pass-through, no inversion, no edge logic.

The Clash standard-library form is
'Clash.Explicit.Synchronizer.dualFlipFlopSynchronizer'; build it here by hand
from two 'register's for the teaching.
-}
synchronize :: (HiddenClockResetEnable dom) => Signal dom Bit -> Signal dom Bit
synchronize i = register high (register high i)

{- | Rising-edge detector: emit a __single one-cycle__ 'True' pulse on each
@False -> True@ transition of the input, and 'False' on every other cycle.

__Law__ (pinned by 'Tests.Button'): exactly one pulse per rising edge; silent
while the input holds steady (whether steadily 'True' or steadily 'False'); silent
on a falling edge. The classic shape is @curr && not prev@ where
@prev = 'register' False curr@.

The Clash standard-library form is 'Clash.Prelude.isRising' (and 'isFalling' for
the dual); build it here by hand for the teaching.
-}
risingEdge :: (HiddenClockResetEnable dom) => Signal dom Bool -> Signal dom Bool
risingEdge = (.&&.) <*> (fmap not . register False)

{- | Toggle flip-flop (a T flip-flop): hold a stored 'Bit', flipping it on every
cycle the input pulse is 'True' and holding it otherwise.

__Law__ (pinned by 'Tests.Button'): seeded 'low'; each 'True' input flips the
stored bit ('complement'); each 'False' holds the previous value. Driven by
'risingEdge' it advances once per button press and stays put between presses.
-}
toggleOn :: (HiddenClockResetEnable dom) => Signal dom Bool -> Signal dom Bit
toggleOn pulse = t
    where
        t = register low (mux pulse (complement <$> t) t)
