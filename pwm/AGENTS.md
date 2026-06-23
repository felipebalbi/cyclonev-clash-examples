# AGENTS.md — pwm

PWM bring-up for the Terasic Cyclone V GX Starter Kit (C5G), laid out to match
the upstream
[clash-starters `orangecrab`](https://github.com/clash-lang/clash-starters/tree/main/orangecrab)
project and the sibling `blinky` example. The follow-on to `blinky`: a
counter+comparator dims an LED instead of just toggling it.

> **Status: scaffold.** Build system only; `src/` and `tests/` hold empty `.hs`
> stubs (`Pwm`, `Pwm.Domain`, `unittests`, `Tests.Pwm`) — the cabal references
> them but they have no bodies yet, so `stack build` / `make` will fail until
> they're written. Everything below about the *build system* is live; anything
> about the PWM circuit is the intended shape, not yet implemented.

## Cross-project deps

None planned. Self-contained, like `blinky`. Pin choices and I/O standards are
read from Terasic's `C5G_Default.qsf`; nothing is copied from it — `pwm.tcl` is
written fresh against the Clash port names.

## Source layout (orangecrab-style)

```
pwm/
  bin/   Clash.hs / Clashi.hs   thin Clash.Main wrappers (clash, clashi exes)
  src/   Pwm.hs                 (TBD) topEntity + pwm component + makeTopEntity
         Pwm/Domain.hs          (TBD) clock domain
  tests/ unittests.hs           (TBD) tasty runner main
         Tests/Pwm.hs           (TBD) duty-cycle assertions / properties
  pwm.tcl                       Quartus project script (device + pins + SDC)
  Makefile  build.cfg           Clash -> Quartus -> program
```

No `src/hw`, `src/sim`, or `src/build` nesting — synthesizable code, the domain,
and tests are split by the top-level `src/` vs `tests/` dirs, like orangecrab.

## Build flow (two stages)

Identical to `blinky`:

1. **Clash → Verilog (stack):** `stack run clash -- Pwm --verilog` →
   `verilog/Pwm.topEntity/topEntity.v` plus `topEntity.sdc`.
2. **Gates → board (make):** the `Makefile` stages the HDL into
   `_build/Pwm/01-hdl/`, builds the Quartus project with `quartus_sh -t pwm.tcl
   Pwm` into `_build/Pwm/02-quartus/`, then runs `quartus_map → quartus_fit →
   quartus_asm → quartus_sta`, and `quartus_pgm`. Tool paths come from
   `build.cfg` (override in `build.cfg.local`). The Makefile also wires in
   stage 1, so a bare `make` is self-contained.

`make` target order: `project` → `synth` → `fit` → `bitstream` (default) →
`program`. `timing` is an off-path convenience target. Select a design with
`NAME` (default `Pwm`), forwarded to `pwm.tcl`.

## Quartus specifics (same as blinky)

- **TCL builds the project; the Makefile runs the stages.** `pwm.tcl` (run via
  `quartus_sh -t pwm.tcl $(NAME)`) only writes the `.qsf`. It reads the design
  name from `$quartus(args)` so a future second top can add design-specific pins
  the way blinky's tcl keys `rst` off the design name.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools are cwd-oriented, so each
  stage `cd`s into `_build/$(NAME)/02-quartus/`. That's why `pwm.tcl` is passed
  by absolute path and uses paths relative to the project dir (`../01-hdl/...`).
- **Pins bind to Clash port names.** `set_location_assignment PIN_R20 -to clk`
  etc. map the `makeTopEntity` ports, not the board labels. A vector output
  (`led :: Signal dom (BitVector 10)`) binds index by index (`led[0]`..`led[9]`);
  `pwm.tcl` carries the full `LEDR[9:0]` map as a commented block for the eventual
  pattern-generator variant.
- **Timing is single-sourced from Clash.** `pwm.tcl` adds the Clash-generated
  `topEntity.sdc` as the `SDC_FILE`; no hand-written SDC.
- **`.sof` is volatile** (SRAM config). `make program` writes it over the
  built-in USB-Blaster; the serial-flash `.pof` path is out of scope.

## Clash notes for when you write the source

- **`makeTopEntity 'topEntity`** must wrap the top so the named-port signature
  fixes the Verilog port names the `.tcl` binds to (`clk`, `led`).
- **Keep `pwm` a reusable, parameterized component** (e.g. resolution as an
  `SNat`), separate from `topEntity`, so it can be unit-tested in isolation and
  reused by a pattern generator later. This mirrors how `blink` was factored.
- **Duty source:** a free-running ramp gives a "breathing" LED with no inputs;
  reading `SW[9:0]` makes the duty interactive (add the switch pins to `pwm.tcl`).
- **Tests:** unlike blinky, PWM has real input→output semantics — assert the
  average of the output stream tracks the duty (a genuine property test).
- The `pwm.cabal` `common-options` (extensions + the load-bearing `ghc-options`)
  are copied from orangecrab — don't trim them.

## What NOT to do

- Don't reintroduce a `Makefile`-less "stack-only" flow or `src/{hw,sim}`
  nesting; follow the upstream clash-starters conventions.
- Don't switch the Makefile to a single `quartus_sh execute_flow` — the staged
  discrete tools are the intended mirror of the reference pipeline.
- Don't bump Clash off the `stack.yaml` pin without updating the `clash-prelude`
  bound in `pwm.cabal`.
- Don't leave the `src/` and `tests/` `.hs` files empty — they're stubs to fill
  in (an empty `.hs` won't compile).
