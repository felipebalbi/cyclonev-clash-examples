# pwm

Pulse-width modulation on the **Terasic Cyclone V GX Starter Kit** (C5G,
`5CGXFC5C6F27C7N`). The follow-on to `blinky`: where blinky just toggled an LED,
PWM *dims* one — a free-running counter is compared against a duty threshold, so
the output's high fraction (and the LED's average brightness) tracks the duty.
Here the duty is a fixed 75 %, so `LEDR[0]` sits at a steady dimmed level. Laid
out to match the upstream clash-starters `orangecrab` project and the sibling
`blinky` example.

Because `pwm` takes the duty as a `Signal` (not a fixed parameter), the very same
component later accepts a *time-varying* duty — a ramp, the switches, a pattern
generator — with no change to its code. The [`pwm-pattern`](../pwm-pattern/)
example does exactly that to make the LED "breathe".

## Layout

```
pwm/
  bin/   Clash.hs / Clashi.hs   thin Clash.Main wrappers (clash, clashi exes)
  src/   Pwm.hs                 topEntity + pwm component + makeTopEntity
         Pwm/Domain.hs          Dom50 (50 MHz) clock domain
  tests/ unittests.hs           tasty runner
         Tests/Pwm.hs           duty-cycle exactness assertions
  pwm.tcl                       Quartus project script (device, pins, SDC)
  Makefile  build.cfg           Clash -> Quartus -> program pipeline
```

`pwm` is a reusable component (the duty width is fixed by its `Signal dom
(Unsigned n)` argument's type), kept separate from `topEntity` so it can be
unit-tested in isolation.

## How it works

A free-running 16-bit counter wraps every `2^16` clocks; the output is high while
the count is below `duty`, so the high fraction is `duty / 2^16`. At 50 MHz the
LED is modulated at `50e6 / 2^16 ≈ 763 Hz` — well above the flicker threshold, so
the eye integrates it into a steady brightness rather than seeing it blink. The
demo's `duty` is ``(maxBound `div` 4) * 3``, i.e. ~75 %.

Like `blinky`, there is **no reset port**: a Cyclone V register powers up at its
`init` value (0) from the configuration bitstream, so the counter starts cleanly;
`topEntity` hands Clash a permanently de-asserted reset, leaving just `clk` and
`led`.

## Build flow (two stages)

Identical to `blinky`:

1. **Clash → Verilog (stack):** `stack run clash -- Pwm --verilog` →
   `verilog/Pwm.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/Pwm/01-hdl/`, builds the Quartus project with `quartus_sh -t pwm.tcl
   Pwm` into `_build/Pwm/02-quartus/`, then runs `quartus_map → quartus_fit →
   quartus_asm → quartus_sta`, and `quartus_pgm` to program.

## Quick start

```sh
stack build       # first run installs GHC + compiles Clash (~10-15 min cold)
stack test        # duty-cycle checks over whole periods (no FPGA needed)
make              # Clash -> Verilog -> Quartus -> _build/Pwm/02-quartus/pwm.sof
make program      # configure the C5G over the built-in USB-Blaster (volatile)
make clean        # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit` /
`bitstream` / `timing`. A second top would drop in as `make NAME=<Module>`.

## Pins

`pwm.tcl` binds the Clash port names to C5G pins (from Terasic's
`C5G_Default.qsf`):

| Clash port | C5G signal | Pin | I/O standard |
|---|---|---|---|
| `clk` | `CLOCK_50_B5B` (50 MHz) | `PIN_R20` | 3.3-V LVTTL |
| `led` | `LEDR[0]` (red LED 0)   | `PIN_F7`  | 2.5 V |

The full `LEDR[9:0]` bank, `SW[9:0]`, and `KEY[3:0]` pin data is in `pwm.tcl` as
commented blocks, ready for designs that grow into them (e.g. `pwm-pattern`).
