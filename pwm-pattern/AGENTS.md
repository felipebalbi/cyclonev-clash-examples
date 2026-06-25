# AGENTS.md — pwm-pattern

Runtime-selectable pattern generators driving a PWM brightness on the Terasic
Cyclone V GX Starter Kit (C5G), laid out to match the upstream clash-starters
`orangecrab` project and the sibling `blinky` / `pwm` examples. The follow-on to
`pwm`: a state machine *generates* the duty (steady or a breathing ramp), built
**two ways** — `moore` and `mealyS` — to compare the constructions. See
`README.md` for the human-facing walkthrough.

## Cross-project deps

None. Self-contained, like `blinky` / `pwm`. Pin choices and I/O standards are
read from Terasic's `C5G_Default.qsf`; nothing is copied — `pwm-pattern.tcl` is
written fresh against the Clash port names (`clk`, `sw`, `led`).

## Source layout (orangecrab-style)

```
pwm-pattern/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PwmMoore.hs / PwmMealy.hs   the two tops (topEntity + makeTopEntity); differ only by runMoore/runMealy
         PwmCore.hs                  counter + comparator + duty shadow register + end-of-period tick
         PwmPattern/Domain.hs        Dom50 clock domain
         PwmPattern/Pattern.hs       the three classes, runMoore / runMealy, prescale, DutyW / PrescaleExp
         PwmPattern/Pattern/Constant.hs   fixed-duty pattern (both instances)
         PwmPattern/Pattern/Triangle.hs   breathing pattern (both instances)
  tests/ unittests.hs               tasty runner
         Tests/PwmCore.hs           shadow-register + end-of-period checks
         Tests/Pattern.hs           per-pattern checks + the moore/mealy Equivalence group
  pwm-pattern.tcl                   Quartus project script (device, pins, SDC)
  Makefile  build.cfg              Clash -> Quartus -> program
```

No `src/hw`, `src/sim`, or `src/build` nesting — synthesizable code, the domain,
and tests split by the top-level `src/` vs `tests/` dirs, like orangecrab.

## Two tops, one project

`PwmMoore` and `PwmMealy` share everything but the driver. `NAME` selects the
**construction** (default `PwmMoore`); it is *not* used to select a pattern:

```
make                       # PwmMoore (moore)
make NAME=PwmMealy         # PwmMealy (mealyS)
```

The **pattern** is selected at *runtime* by `SW[0]` (`sw` low = `Constant`, high =
`Triangle`): each top instantiates both patterns in parallel and `mux`es their
duty outputs. `NAME` keys the build tree (`_build/$(NAME)/...`) so the two
`topEntity`s never collide, and is forwarded to `pwm-pattern.tcl` (which ignores
it — both tops share the same pins).

## Build flow (two stages)

Identical to `blinky` / `pwm`:

1. **Clash → Verilog (stack):** `stack run clash -- $(NAME) --verilog` →
   `verilog/$(NAME).topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Gates → board (make):** stage HDL into `_build/$(NAME)/01-hdl/`, build the
   Quartus project with `quartus_sh -t pwm-pattern.tcl $(NAME)` into
   `_build/$(NAME)/02-quartus/`, then `quartus_map → quartus_fit → quartus_asm →
   quartus_sta`, and `quartus_pgm`. Tool paths from `build.cfg`.

`make` target order: `project` → `synth` → `fit` → `bitstream` (default) →
`program`. `timing` is off-path.

## Quartus specifics (same as blinky / pwm)

- **TCL builds the project; the Makefile runs the stages.** `pwm-pattern.tcl`
  (run via `quartus_sh -t pwm-pattern.tcl $(NAME)`) only writes the `.qsf`. Its
  `project_new` name is `pwm-pattern`, matching the Makefile's `QPROJ` so the
  discrete stages (`quartus_map pwm-pattern`, …) find the revision. Both tops
  share ports, so — unlike blinky's conditional `rst` — there is **no `$design`
  pin branch**.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools are cwd-oriented; the `.tcl`
  is passed by absolute path and uses paths relative to the project dir
  (`../01-hdl/...`).
- **Pins bind to Clash port names.** `clk → PIN_R20` (3.3-V LVTTL), `led → PIN_F7`
  (2.5 V), `sw → PIN_AC9` (`SW[0]`, 1.2 V). Change a port name in `src/` and the
  `.tcl` must follow.
- **Timing is single-sourced from Clash.** `pwm-pattern.tcl` adds the generated
  `topEntity.sdc` as the `SDC_FILE`; no hand-written SDC.
- **Device string is `5CGXFC5C6F27C7`** — drop the trailing `N`, or `quartus_map`
  errors "Part name … is illegal".
- **`.sof` is volatile** (SRAM config); the serial-flash `.pof` path is out of scope.

## Clash notes

- **`makeTopEntity 'topEntity`** fixes the Verilog port names (`clk`/`sw`/`led`)
  the `.tcl` binds to. No reset port: the tops pass `unsafeFromActiveHigh (pure
  False)`, relying on Cyclone V power-up `init` like `blinky`/`pwm`.
- **The clocked circuit is a constrained helper.** Each top is
  `withClockResetEnable clk noReset enableGen (patternLed sw)`, where
  `patternLed :: HiddenClockResetEnable dom => ...`. The circuit logic must live
  in a binding that *carries* the `HiddenClockResetEnable` constraint — a flat
  `where` block on `topEntity` puts the clocked primitives outside
  `withClockResetEnable`'s reach and fails with "unbound implicit parameters".
- **Patterns are re-authored in two classes.** `PatGenMoore` (`next` + `duty`) and
  `PatGenMealy` (`step :: Bool -> State a (...)`, strict `Control.Monad.State`).
  `step` returns the **pre-update** duty so `runMealy ≡ runMoore` — the
  `Equivalence` test guards it. Don't make one instance call the other; the point
  is to show both spellings.
- **Latch gotcha — `Constant` is intentionally state-less.** A pattern whose
  `mealyS` `step` never `put`s emits a bare self-hold register (`x1_0 <= x1_0`);
  with no reset, Quartus infers a **latch** (Warning 10240) that drops the value
  on hardware (the LED stays off). `Constant` therefore carries **no field** —
  its duty is the wired literal `constDuty`, like `pwm`. Don't re-add a field /
  stored level to `Constant`. (`Triangle` is fine: its state is genuinely driven.)
- **Rate: enable, not clock.** The PWM carrier runs at full clock speed (~763 Hz);
  only the pattern *advance* is gated, by `prescale (SNat @PrescaleExp)` on the
  end-of-period tick. Don't divide the core clock — the carrier must stay fast or
  the LED flickers.
- The `pwm-pattern.cabal` `common-options` (extensions + load-bearing
  `ghc-options`) come from orangecrab — don't trim them. `mtl` is a dependency for
  `Control.Monad.State.Strict` (the `mealyS` driver).

## Tests

`stack test` runs the tasty suite (pure Haskell, no FPGA): `Tests.PwmCore`
(shadow register + end-of-period cadence + duty exactness) and `Tests.Pattern`
(per-pattern `next`/`duty`/`step` checks, the prescaler, and the **Equivalence**
group asserting `runMoore ≡ runMealy`). Keep the equivalence test — it is what
makes "two spellings, one waveform" a fact rather than a comment.

## What NOT to do

- Don't select the pattern with a `PATTERN=` make variable — threading a CLI
  string into Haskell type selection needs CPP / cabal flags / templating, i.e.
  build infrastructure beyond the existing toolchain. Patterns are runtime-`mux`ed
  on `SW[0]`; `NAME` only picks the construction.
- Don't re-add a stored level/field to `Constant` (latch — see the Clash notes),
  and don't give the tops a reset port (the no-reset power-up design is
  deliberate; `PwmMoore` proves it works).
- Don't divide the core clock to slow the animation — gate the pattern advance
  with the prescaled enable instead.
- Don't reintroduce a `Makefile`-less "stack-only" flow or `src/{hw,sim}` nesting,
  and don't collapse the staged Quartus tools into one `execute_flow`.
- Don't bump Clash off the `stack.yaml` pin without updating the `clash-prelude`
  bound in `pwm-pattern.cabal`.
