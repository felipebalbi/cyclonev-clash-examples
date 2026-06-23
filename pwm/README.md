# pwm

Pulse-width modulation on the **Terasic Cyclone V GX Starter Kit** (C5G,
`5CGXFC5C6F27C7N`). The follow-on to `blinky`: where blinky just toggled an LED,
PWM dims one — a counter+comparator produces a duty-cycled output, so a ramped
duty makes `LEDR[0]` "breathe". Laid out to match the upstream clash-starters
`orangecrab` project and the sibling `blinky` example.

> **Status: scaffold.** The build system (Makefile, `pwm.tcl`, cabal, stack,
> editor config) is in place, and `src/`/`tests/` hold **empty `.hs` stubs** with
> the right names — the Clash source hasn't been written yet. `stack build` /
> `make` won't succeed until the modules below have bodies. See "Filling in the
> scaffold".

## Layout

```
pwm/
  bin/   Clash.hs / Clashi.hs   thin Clash.Main wrappers (clash, clashi exes)
  src/   Pwm.hs                 (TBD) topEntity + pwm component + makeTopEntity
         Pwm/Domain.hs          (TBD) clock domain (mirror Blinky/Domain.hs)
  tests/ unittests.hs           (TBD) tasty runner
         Tests/Pwm.hs           (TBD) duty-cycle assertions / properties
  pwm.tcl                       Quartus project script (device, pins, SDC)
  Makefile  build.cfg           Clash -> Quartus -> program pipeline
```

## Filling in the scaffold

The cabal references these modules and the files exist as empty stubs; give them
bodies to make it build:

1. **`src/Pwm/Domain.hs`** — a clock domain. Copy `blinky`'s `Dom50` (50 MHz)
   unless you want a different rate.
2. **`src/Pwm.hs`** — a reusable `pwm` component plus `topEntity` (with
   `makeTopEntity 'topEntity`). Keep the port names matching `pwm.tcl`
   (`clk`, `led`) — or update the tcl if you choose others.
3. **`tests/unittests.hs`** + **`tests/Tests/Pwm.hs`** — PWM has real data
   behaviour (duty in → average out), so this is a good place for a proper
   property test, unlike blinky's trivial toggle check.

`pwm.tcl` also carries a commented `LEDR[9:0]` bank mapping and notes on
`SW[9:0]` / `KEY[3:0]`, ready for when the design grows into a pattern generator
across all the LEDs.

## Build flow (two stages)

Identical to `blinky`:

1. **Clash → Verilog (stack):** `stack run clash -- Pwm --verilog` →
   `verilog/Pwm.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/Pwm/01-hdl/`, builds the Quartus project with `quartus_sh -t pwm.tcl
   Pwm` into `_build/Pwm/02-quartus/`, then runs `quartus_map → quartus_fit →
   quartus_asm → quartus_sta`, and `quartus_pgm` to program.

## Quick start (once src/ is populated)

```sh
stack build       # first run installs GHC + compiles Clash (~10-15 min cold)
stack test        # property-test the pwm component
make              # Clash -> Verilog -> Quartus -> _build/Pwm/02-quartus/pwm.sof
make program      # configure the C5G over the built-in USB-Blaster (volatile)
make clean        # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit`
/ `bitstream` / `timing`. A second top drops in as `make NAME=<Module>`.

## Pins (scaffold default)

`pwm.tcl` binds the Clash port names to C5G pins (from Terasic's
`C5G_Default.qsf`). The default assumes a single PWM-driven LED:

| Clash port | C5G signal | Pin | I/O standard |
|---|---|---|---|
| `clk` | `CLOCK_50_B5B` (50 MHz) | `PIN_R20` | 3.3-V LVTTL |
| `led` | `LEDR[0]` (red LED 0)   | `PIN_F7`  | 2.5 V |

The full `LEDR[9:0]` bank, `SW[9:0]`, and `KEY[3:0]` pin data is in `pwm.tcl` as
commented blocks — uncomment as the design needs them.
