# AGENTS.md

Conventions for AI agents (Copilot, Codex, Cursor, Aider, …) and human
contributors working in this repository. Per-project specifics live in
`<project>/AGENTS.md` and override anything below.

## Repo overview

Bottom-up [Clash](https://clash-lang.org/) (Haskell HDL) bring-up examples for
the **Terasic Cyclone V GX Starter Kit** (C5G, Intel/Altera `5CGXFC5C6F27C7N`).
It is the Quartus sibling of `icebreaker-clash-examples`: same clash-starters
front end, but the gates → board backend is **Quartus Prime Lite** instead of
`yosys/nextpnr/icepack/iceprog`. Each top-level directory is a self-contained
example laid out to match the upstream
[clash-starters](https://github.com/clash-lang/clash-starters) projects
(notably `orangecrab`).

```
blinky/
```

## Project layout (per example)

Mirrors the upstream clash-starters layout — **not** the SpinalHDL repo's
`src/{hw,sim}` shape:

```
<project>/
  bin/    Clash.hs / Clashi.hs    thin Clash.Main wrappers (clash, clashi exes)
  src/    <Top>.hs + helpers      synthesizable code; one module owns topEntity
  tests/  unittests.hs + Tests/   tasty test-suite, run via `stack test`
  <project>.cabal  stack.yaml
  hie.yaml                       pins the HLS cradle to stack components
  .dir-locals.el                 points haskell-mode's C-c C-l at the clashi REPL
  Makefile  build.cfg            gates + programming (quartus_map/fit/asm/sta/pgm)
  <project>.tcl                  Quartus project-generation script (device + pins)
```

## Build flow (two stages)

Standard Clash architecture, same as upstream clash-starters:

1. **Clash → Verilog (stack):** `stack run clash -- <Top> --verilog`.
   The `bin/Clash.hs` wrapper is a verbatim `Clash.Main.defaultMain` shim.
2. **Verilog → bitstream → board (make):** the `Makefile` drives Quartus as a
   staged pipeline — `quartus_sh -t <project>.tcl` (project + pins) then
   `quartus_map → quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm`
   for JTAG programming. Tool paths are factored into `build.cfg` (overridable
   via a gitignored `build.cfg.local`). The Makefile also invokes stage 1 so a
   bare `make` is self-contained.

`stack test` runs each project's tasty suite.

## Quartus specifics

- **TCL builds the project; the Makefile runs the stages.** `<project>.tcl`
  (run via `quartus_sh -t`) writes device, pins, source files, and SDC into the
  generated `<project>.qsf`. Each compile stage is then a discrete Quartus CLI
  executable, mirroring the reference repo's discrete yosys/nextpnr/icepack/iceprog.
- **Pins bind to the Clash port names.** Quartus assignments map the
  `makeTopEntity` port names (`clk`, `led`) to pin **locations** and **I/O
  standards**, not to Terasic's board labels (`CLOCK_50_B5B`, `LEDR[0]`).
- **Timing comes from Clash's generated `topEntity.sdc`.** No hand-written SDC;
  the clock constraint always tracks the Clash clock domain's period.
- **Quartus CLI is cwd-oriented.** Recipes `cd` into the per-project build dir
  (`_build/02-quartus/`) before invoking `quartus_*`. This is the Quartus
  equivalent of passing a project path, not a style departure to "fix".
- **`.sof` is volatile** (SRAM configuration, lost on power cycle). Flash
  (`.pof`) programming is intentionally out of scope for these smoke tests.

## File conventions

- **LF line endings only.** Run `dos2unix` on anything edited on a Windows host.
- Directory names are **lowercase** (`blinky/`, not `Blinky/`). Haskell module
  identifiers must stay capitalized (`module Blinky`), and a project's top
  entity keeps the upstream name `topEntity`.
- The `<project>.cabal` `common-options` (extensions + `ghc-options`) are
  adopted from the clash-starters projects and are load-bearing for Clash —
  don't trim them.
- **`hie.yaml` must enumerate cradle components.** Each project's cabal builds
  two executables (`clash`, `clashi`), each with its own `main-is`, so a bare
  `cradle: stack:` leaves `stack repl` unable to pick a main module. List the
  components by path instead (lib / exe:clash / exe:clashi / test).
- **`.dir-locals.el` points the REPL at `clashi`.** Editor config like
  `hie.yaml`; needs `interactive-haskell-mode` enabled.

## Comment / Haddock style

- **Why, not what.** Comments add the rationale a reader can't recover from the
  code: electrical reasons, protocol corners, choices between alternatives.
- Match the depth of `blinky/src/Blinky.hs` (Components, with a design-rationale
  header) and `blinky/src/Blinky/Domain.hs` (terse, for the domain).
- Doc-link breadcrumbs (Clash stdlib pages, datasheet sections) are welcome.

## Commit conventions

- Short imperative subject lines.
- AI-pair-programmed commits include the trailer:
  ```
  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
  ```

## What NOT to do

- Don't add lint/build/test infrastructure beyond the existing toolchain
  (stack, Quartus Prime Lite). It's intentional. (`hie.yaml` and `.dir-locals.el`
  are not build tooling — they're editor config; keep them.)
- Don't run sims or builds the user didn't ask for; running an existing
  `stack test` after a change is fine.
- Don't create planning `.md` files inside the repo. Use the per-session
  workspace for ephemeral plans.
- Don't restructure an example away from the upstream clash-starters layout
  (no `src/{hw,sim,build}` nesting).
- Don't give the no-reset `Blinky` top a reset (it relies on the Cyclone V
  power-up `init` value, exactly like the reference); if you need a reset, use
  the `BlinkyWithReset` top, which synchronizes the active-low KEY0 button rather
  than driving the LED through a raw reset net.
