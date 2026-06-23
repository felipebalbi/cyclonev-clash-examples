# blinky

The "hello world" of the Clash → Quartus → board toolchain for the **Terasic
Cyclone V GX Starter Kit** (C5G, `5CGXFC5C6F27C7N`): a free-running counter
divides the 50 MHz board clock and its top bit drives an on-board red LED
(`LEDR[0]`), blinking at ~1.34 s. Laid out to match the upstream clash-starters
`orangecrab` project.

Two top entities share the project, selected with `NAME` (default `Blinky`):

| `NAME` | Ports | What it does |
|---|---|---|
| `Blinky` | `clk`, `led` | LED free-runs; no reset (power-up `init`). |
| `BlinkyWithReset` | `clk`, `rst`, `led` | Same blink, but held in reset while KEY0 is pressed. |

## Layout

```
blinky/
  bin/   Clash.hs / Clashi.hs   thin Clash.Main wrappers (clash, clashi exes)
  src/   Blinky.hs              topEntity + counter + makeTopEntity
         Blinky/Domain.hs       Dom50 (50 MHz) clock domain
         BlinkyWithReset.hs     KEY0 (active-low) -> 2-FF reset synchronizer
  tests/ unittests.hs           tasty runner
         Tests/Blinky.hs        the LED-toggles assertion
  blinky.tcl                    Quartus project script (device, pins, SDC)
  Makefile  build.cfg           Clash -> Quartus -> program pipeline
```

`BlinkyWithReset` reuses `Blinky`'s `blink` and `CounterWidth` unchanged — only
the reset wiring is new.

## Build flow (two stages)

1. **Clash → Verilog (stack):** `stack run clash -- $(NAME) --verilog`, driven by
   `bin/Clash.hs`. Output: `verilog/$(NAME).topEntity/topEntity.v` (+ a
   `topEntity.sdc` carrying the 50 MHz clock constraint).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/$(NAME)/01-hdl/`, generates the Quartus project with `quartus_sh -t
   blinky.tcl $(NAME)` into `_build/$(NAME)/02-quartus/`, then runs the discrete
   Quartus stages `quartus_map → quartus_fit → quartus_asm → quartus_sta`, and
   `quartus_pgm` to program. Tool paths come from `build.cfg` (override in
   `build.cfg.local`). Each design gets its own `_build/$(NAME)/` subtree, so the
   two `topEntity`s never collide.

## Quick start

```sh
stack build                     # first run installs GHC + compiles Clash (~10-15 min cold)
stack test                      # pure-Haskell toggle check, no FPGA needed

make                            # plain Blinky  -> _build/Blinky/02-quartus/blinky.sof
make program                    # configure the C5G over the built-in USB-Blaster (volatile)

make NAME=BlinkyWithReset         # reset variant -> _build/BlinkyWithReset/02-quartus/blinky.sof
make program NAME=BlinkyWithReset # ... and program it

make timing                     # optional: quartus_sta slack report (add NAME= as needed)
make clean                      # remove _build/ and verilog/
```

`make` stops at the `.sof`. Individual stages are available as targets:
`make project` / `synth` / `fit` / `bitstream` / `timing` (each honours `NAME=`).

## Pins

The Quartus assignments in `blinky.tcl` bind the Clash port names (not the
Terasic board labels) to pin locations and I/O standards, taken from Terasic's
`C5G_Default.qsf`:

| Clash port | C5G signal | Pin | I/O standard | Designs |
|---|---|---|---|---|
| `clk` | `CLOCK_50_B5B` (50 MHz)  | `PIN_R20` | 3.3-V LVTTL | both |
| `led` | `LEDR[0]` (red LED 0)    | `PIN_F7`  | 2.5 V       | both |
| `rst` | `KEY[0]` (push button)   | `PIN_P11` | 1.2 V       | `BlinkyWithReset` only |

`rst` is added by `blinky.tcl` only when `NAME=BlinkyWithReset`, so plain Blinky
draws no "assignment to a nonexistent node" warning.

## Programming notes

- The C5G has a **built-in USB-Blaster**; no external programmer is needed.
- `make program` runs `quartus_pgm -m jtag -o "p;blinky.sof"`. If `jtagconfig`
  shows no cable, check the USB connection / udev permissions (`jtagd`). If more
  than one cable/device is present, add `-c <cable>` or `@<n>` to the `-o`.
- `.sof` configures the FPGA's SRAM and is **lost on power cycle**. Writing the
  serial-flash `.pof` is out of scope for this smoke test.

## Reset: the two variants

- **`Blinky`** has no reset pin: a Cyclone V register powers up at its `init`
  value (0) from the configuration bitstream, so the divider starts cleanly.
  `topEntity` hands Clash a permanently de-asserted reset, so Clash emits no
  `reset` port — just `clk` and `led`.
- **`BlinkyWithReset`** drives the reset from KEY0. The button is active-low,
  asynchronous, and bouncy, so the raw pin is run through `resetSynchronizer`
  (async-assert / 2-FF synchronous-deassert) before it reaches the counter.
  Holding KEY0 keeps the LED reset to 0; releasing restarts the blink. See the
  module headers in `src/Blinky.hs` and `src/BlinkyWithReset.hs`.
