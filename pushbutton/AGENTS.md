# AGENTS.md — pushbutton

A **pushbutton-toggled LED** on the Terasic Cyclone V GX Starter Kit (C5G): press
`KEY0`, `LEDR[0]` flips and holds until the next press. Laid out to match the
upstream clash-starters `orangecrab` project and the sibling `blinky` / `pwm` /
`pwm-pattern` / `pwm-wave` / `sevenseg` examples. See `README.md` for the
human-facing walkthrough.

The teaching axis is three tiny **clocked** primitives — a 2-FF input
**synchronizer**, a rising-edge **detector**, and a **toggle** flip-flop — plus
the active-low→data polarity flip. These are the building blocks of every async
input downstream (UART RX start-bit detect, keypad scan). Self-contained.

## Cross-project deps

None. Self-contained, like the siblings. The reuse from `BlinkyWithReset` is by
*pattern* (the same 2-FF synchronizer), not shared code. Pin choices and I/O
standards are read from Terasic's `C5G_Default.qsf`; nothing is copied —
`pushbutton.tcl` is written fresh against the Clash port names (`clk`, `key0`,
`led`).

## Source layout (orangecrab-style)

```
pushbutton/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PushButton.hs               top: topEntity + toggleLed + makeTopEntity
         PushButton/Domain.hs        Dom50 clock domain
         PushButton/Button.hs        synchronize + risingEdge + toggleOn
  tests/ unittests.hs               tasty runner
         Tests/Button.hs            primitive laws + active-low polarity + capstone
  pushbutton.tcl                     Quartus project script (device, pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program
```

No `src/hw`, `src/sim`, or `src/build` nesting — synthesizable code, the domain,
and tests split by the top-level `src/` vs `tests/` dirs, like orangecrab.

## One top, no variants

A **single** `topEntity` (`PushButton`). `NAME` survives in the Makefile only for
parity with the sibling build machinery (and to key `_build/$(NAME)/`); it is
`PushButton` and is forwarded to (but unused by) `pushbutton.tcl`.

## Build flow (two stages)

Identical to the siblings:

1. **Clash → Verilog (stack):** `stack run clash -- PushButton --verilog` →
   `verilog/PushButton.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Gates → board (make):** stage HDL into `_build/PushButton/01-hdl/`, build the
   Quartus project with `quartus_sh -t pushbutton.tcl PushButton` into
   `_build/PushButton/02-quartus/`, then `quartus_map → quartus_fit → quartus_asm
   → quartus_sta`, and `quartus_pgm`. Tool paths from `build.cfg`.

## Quartus specifics (same as the siblings, plus a three-way I/O split)

- **TCL builds the project; the Makefile runs the stages.** `pushbutton.tcl` (run
  via `quartus_sh -t pushbutton.tcl PushButton`) only writes the `.qsf`. Its
  `project_new` name is `pushbutton`, matching the Makefile's `QPROJ` so the
  discrete stages (`quartus_map pushbutton`, …) find the revision.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools are cwd-oriented; the `.tcl`
  is passed by absolute path and uses paths relative to the project dir
  (`../01-hdl/...`).
- **Three ports, three I/O standards.** `clk` is 3.3-V LVTTL (`R20`), `key0` is
  **1.2 V** (`P11`), `led` is **2.5 V** (`F7`) — each port carries its own
  standard. Change a port name in `src/` and the `.tcl` must follow.
- **Timing is single-sourced from Clash.** `pushbutton.tcl` adds the generated
  `topEntity.sdc` as the `SDC_FILE`; no hand-written SDC.
- **Device string is `5CGXFC5C6F27C7`** — drop the trailing `N`, or `quartus_map`
  errors "Part name … is illegal".
- **`.sof` is volatile** (SRAM config); the serial-flash `.pof` path is out of scope.

## Clash notes (pushbutton specifics)

- **Synchronize ≠ debounce.** The crux. The C5G `KEY`s are RC-filtered in
  hardware (no bounce), but still async to `Dom50`, so `synchronize` (two cascaded
  `register`s) is the metastability hardener — not optional. Stdlib form:
  `Clash.Explicit.Synchronizer.dualFlipFlopSynchronizer`; built by hand here.
- **Seed the synchronizer to idle.** `register high (register high i)` — `high` is
  the released level, so power-up doesn't read a phantom press. The latency law is
  seed-independent, but the seed sets the power-up polarity.
- **Active-low button → a press is a falling edge.** `toggleLed` inverts with
  `fmap (== low)` so "pressed" is `True` and `risingEdge` reads a normal rising
  edge. A polarity test pins this so it isn't assumed.
- **No reset.** `topEntity` passes `unsafeFromActiveHigh (pure False)` so the
  toggle powers up `low` via Cyclone V `init`; Clash emits no `reset` port. The
  clocked logic lives in the constrained helper `toggleLed`
  (`HiddenClockResetEnable`); a flat `where` on `topEntity` fails with "unbound
  implicit parameters". For a clear button, synchronize a *separate* KEY into a
  `Reset` (à la `BlinkyWithReset`); don't drive the LED through a raw reset net.
- **FFs, not latches.** Every branch drives a real register value (the
  `register`/`complement` style), so `quartus_map` infers flip-flops. If a build
  "works in sim, not on hardware," read the Verilog + `quartus_map` (Warning
  10240), don't guess.
- **`Bit`, not `Bool`, at the edges.** `key0`/`led` are `Bit`; flip with
  `complement`, not `Bool`'s `not`. The cabal `common-options` come from orangecrab
  — don't trim them. No `mtl` (no `State`/`mealyS` here).

## Tests

`stack test` runs the tasty suite (pure Haskell, no FPGA): `Tests.Button` pins
each primitive's law (synchronizer = 2-cycle delay, edge = one pulse per rising
edge, toggle = alternate/hold seeded low), the active-low polarity, and a capstone
that drives a press waveform — including a held press — and counts LED toggles
over a settled window (one per *new* press, held ignored). The end-to-end cases
drop a short warm-up so they're robust to the synchronizer seed and pipeline
latency.

## What NOT to do

- **Don't add firmware debounce** — the KEYs are RC-filtered in hardware.
- **Don't skip the 2-FF synchronizer** — debounce ≠ metastability hardening.
- **Don't give the top a reset port** (no-reset power-up is deliberate); if you
  need a clear, synchronize a separate KEY like `BlinkyWithReset`.
- Don't use `Bool`'s `not` on a `Bit` (use `complement`), and don't compare
  signals with `if`/`then` (use `mux`).
- Don't hand-write SDC (single-source from Clash's `topEntity.sdc`), trim the
  cabal `common-options`, reintroduce `src/{hw,sim}` nesting, collapse the staged
  Quartus tools into one `execute_flow`, or bump Clash off the `stack.yaml` pin
  without updating the `clash-prelude` bound.
