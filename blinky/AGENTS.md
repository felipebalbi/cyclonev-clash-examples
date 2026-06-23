# AGENTS.md — blinky

Clash blinking-LED bring-up for the Terasic Cyclone V GX Starter Kit (C5G),
laid out to match the upstream
[clash-starters `orangecrab`](https://github.com/clash-lang/clash-starters/tree/main/orangecrab)
project. The Quartus/Cyclone V retarget of the sibling
`icebreaker-clash-examples` blinky.

## Cross-project deps

None. Self-contained. The pin choices (`clk` → R20, `led` → F7, `rst` → P11) and
I/O standards are read from Terasic's `C5G_Default.qsf`; nothing is copied from
it — `blinky.tcl` is written fresh against the Clash port names (`clk`, `led`,
`rst`).

## Source layout (orangecrab-style)

```
blinky/
  bin/   Clash.hs / Clashi.hs   thin Clash.Main wrappers (clash, clashi exes)
  src/   Blinky.hs              topEntity + counter + makeTopEntity
         Blinky/Domain.hs       Dom50 (50 MHz) clock domain
         BlinkyWithReset.hs     KEY0 (active-low) -> 2-FF reset synchronizer
  tests/ unittests.hs           tasty runner main
         Tests/Blinky.hs        the toggle assertion
  blinky.tcl                    Quartus project script (device + pins + SDC)
  Makefile  build.cfg           Clash -> Quartus -> program
```

There is **no `src/hw`, `src/sim`, or `src/build`** here — that nesting belongs
to the SpinalHDL repo. Synthesizable code, the domain, and tests are split by
the top-level `src/` vs `tests/` dirs, exactly like orangecrab.

## Two designs, one project

`Blinky` and `BlinkyWithReset` share everything but the reset wiring.
`BlinkyWithReset` `import`s `Blinky`'s `blink` and `CounterWidth` unchanged.
Select with `NAME` (default `Blinky`):

```
make                        # Blinky
make NAME=BlinkyWithReset   # reset variant
```

`NAME` keys the build tree (`_build/$(NAME)/...`) so the two `topEntity`s never
masquerade as each other, and is forwarded to `blinky.tcl` so it adds the `rst`
pin only for the reset variant.

## Build flow (two stages)

1. **Clash → Verilog (stack):** `stack run clash -- Blinky --verilog`, which the
   `bin/Clash.hs` wrapper drives. Output: `verilog/Blinky.topEntity/topEntity.v`
   plus `topEntity.sdc`.
2. **Gates → board (make):** the `Makefile` stages the HDL into `_build/01-hdl/`,
   builds the Quartus project with `quartus_sh -t blinky.tcl` into
   `_build/02-quartus/`, then runs the discrete stages `quartus_map →
   quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm` to program. Tool
   paths come from `build.cfg` (override in `build.cfg.local`). The Makefile also
   wires in stage 1, so a bare `make` is self-contained.

`make` target order: `project` → `synth` → `fit` → `bitstream` (default) →
`program`. `timing` is an off-path convenience target. The Makefile is the
Quartus retarget of orangecrab's ECP5 one (`quartus_*` replace
`yosys/nextpnr/ecppack`).

## Quartus gotchas worth remembering

- **TCL builds the project; the Makefile runs the stages.** `blinky.tcl` (run
  via `quartus_sh -t blinky.tcl $(NAME)`) only writes the `.qsf` (device, top,
  sources, SDC, pins). It serves **both** designs: it reads the design name from
  `$quartus(args)` and adds the `rst` pin only for `BlinkyWithReset` — the
  single-file analogue of the reference repo's two per-design pcf files.
  Synthesis/fit/assemble/timing are discrete CLI tools driven by the Makefile —
  the deliberate analogue of the reference's discrete
  yosys/nextpnr/icepack/iceprog stages, *not* a single `execute_flow`.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools operate on the project in the
  current working directory, so each stage `cd`s into `_build/$(NAME)/02-quartus/`.
  That is why `blinky.tcl` is passed by **absolute** path (`$(abspath ...)`) and
  uses paths relative to the project dir (`../01-hdl/...`). Don't "fix" the `cd`.
- **Pins bind to Clash port names.** `set_location_assignment PIN_R20 -to clk`
  etc. map the `makeTopEntity` ports, not the board labels `CLOCK_50_B5B` /
  `LEDR[0]`. Change a port name in `src/` and the `.tcl` must follow.
- **Timing is single-sourced from Clash.** `blinky.tcl` adds the
  Clash-generated `topEntity.sdc` (50 MHz, from `Dom50`) as the `SDC_FILE`; there
  is no hand-written SDC. Bump the domain period and the constraint tracks it.
- **`.sof` is volatile** (SRAM config). `make program` writes it over the
  built-in USB-Blaster; the serial-flash `.pof` path is out of scope.

## Clash gotchas worth remembering

- **`makeTopEntity 'topEntity`** derives the `Synthesize` annotation from the
  named-port type signature (`"clk" ::: Clock Dom50 -> "led" ::: Signal Dom50 Bit`).
  Without it, Clash invents port/module names and the `.tcl` pins stop binding.
- **`Blinky` has no reset port by design.** A Cyclone V register powers up at its
  `init` value (0) from the bitstream, so the counter starts cleanly with no
  reset pin; `Blinky.topEntity` passes `unsafeFromActiveHigh (pure False)` and
  Clash emits no `reset` port. Don't "add a reset for safety" to `Blinky` — use
  `BlinkyWithReset` if you want one.
- **`BlinkyWithReset` synchronizes its reset.** KEY0 is active-low, async, and
  bouncy, so the raw pin goes through `resetSynchronizer clk (unsafeFromActiveLow
  ...)` — async-assert / 2-FF synchronous-deassert — before reaching the counter.
  Don't feed the raw `rst` pin straight into a `Reset`; the synchronizer is the
  whole point of the variant. No debounce is needed for a reset.
- **`register 0 (counter + 1)`** is the whole counter. The recursive `let` is
  not an infinite loop: `register` delays its argument by one cycle.
- **`blink` takes the width as an `SNat n`** so the same circuit elaborates at
  width 26 for synthesis and a small width for the test. `topEntity` applies
  `SNat @CounterWidth`.
- The `blinky.cabal` `common-options` (extensions + the load-bearing
  `ghc-options`: `-fexpose-all-unfoldings`, `-fno-worker-wrapper`,
  `-fno-unbox-*-strict-fields`, the three typelits plugins) are copied from
  orangecrab — don't trim them.

## Tests

- `stack test` runs the tasty suite. Blinky has no data inputs, so there is no
  hedgehog property to write; the test `sampleN`s a small-width instance and
  asserts the LED toggles. Plain Haskell on the output stream — no simulator,
  independent of Quartus.

## What NOT to do

- Don't reintroduce a `Makefile`-less "stack-only" flow or `src/{hw,sim}`
  nesting; the point is to follow the upstream clash-starters conventions.
- Don't switch the Makefile to a single `quartus_sh execute_flow` — the staged
  discrete tools are the intended mirror of the reference pipeline.
- Don't bump Clash off the `stack.yaml` pin without updating the `clash-prelude`
  bound in `blinky.cabal`.
- Don't give `Blinky` a reset, and don't feed `BlinkyWithReset`'s raw KEY0 pin
  into a `Reset` unsynchronized — see the two reset notes above. The LED is
  always just the counter MSB, never driven by a reset net directly.
