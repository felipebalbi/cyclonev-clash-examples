# AGENTS.md — pwm-wave

A PWM brightness **wave** (Larson/KITT scanner) on the Terasic Cyclone V GX
Starter Kit (C5G), laid out to match the upstream clash-starters `orangecrab`
project and the sibling `blinky` / `pwm` / `pwm-pattern` examples. The follow-on
to `pwm-pattern`: a single glowing bump ping-pongs across `LEDR[9:0]` while a
counter-rotating bump sweeps `LEDG[7:0]`, every LED dimmed by per-lane PWM. See
`README.md` for the human-facing walkthrough.

The teaching axis is **vectors** (not moore-vs-mealy): `Vec n Bit` ports, a
vectorized PWM core, and `imap`/`reverse` spatial decode. `SW[0]` adds a runtime
choice of brightness falloff — linear triangle vs a **gamma** curve in the repo's
first on-chip ROM (`PwmWave.Gamma`).

## Cross-project deps

None. Self-contained, like the siblings. Pin choices and I/O standards are read
from Terasic's `C5G_Default.qsf`; nothing is copied — `pwm-wave.tcl` is written
fresh against the Clash port names (`clk`, `sw`, `ledr`, `ledg`).

## Source layout (orangecrab-style)

```
pwm-wave/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PwmWave.hs                  top: topEntity + waveLeds + makeTopEntity
         PwmWave/Domain.hs           Dom50 clock domain
         PwmWave/Core.hs             pwmVec — vectorized PWM (one carrier, N comparators, Vec shadow, eop tick)
         PwmWave/Wave.hs             triangleKernel + Wave position machine + bumpVec/red/greenDuties + prescale
         PwmWave/Gamma.hs            gamma LUT in on-chip ROM (gammaKernel = gammaCorrect . triangleKernel)
  tests/ unittests.hs               tasty runner
         Tests/PwmWaveCore.hs        per-lane duty exactness + Vec shadow + eop cadence
         Tests/Wave.hs              kernel shape + decode + counter-rotation + position ping-pong
         Tests/Gamma.hs             gamma table + kernel shape + the "gamma darkens" property
  pwm-wave.tcl                       Quartus project script (device, pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program
```

No `src/hw`, `src/sim`, or `src/build` nesting — synthesizable code, the domain,
and tests split by the top-level `src/` vs `tests/` dirs, like orangecrab.

## One top, no variants

Unlike `pwm-pattern` (which keyed `NAME` to the moore/mealy construction), this
example has a **single** `topEntity` (`PwmWave`). `NAME` survives in the Makefile
only for parity with the sibling build machinery (and to key `_build/$(NAME)/`);
it is `PwmWave` and is forwarded to (but unused by) `pwm-wave.tcl`.

## Build flow (two stages)

Identical to the siblings:

1. **Clash → Verilog (stack):** `stack run clash -- PwmWave --verilog` →
   `verilog/PwmWave.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Gates → board (make):** stage HDL into `_build/PwmWave/01-hdl/`, build the
   Quartus project with `quartus_sh -t pwm-wave.tcl PwmWave` into
   `_build/PwmWave/02-quartus/`, then `quartus_map → quartus_fit → quartus_asm →
   quartus_sta`, and `quartus_pgm`. Tool paths from `build.cfg`.

## Quartus specifics (same as the siblings)

- **TCL builds the project; the Makefile runs the stages.** `pwm-wave.tcl` (run
  via `quartus_sh -t pwm-wave.tcl PwmWave`) only writes the `.qsf`. Its
  `project_new` name is `pwm-wave`, matching the Makefile's `QPROJ` so the
  discrete stages (`quartus_map pwm-wave`, …) find the revision.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools are cwd-oriented; the `.tcl`
  is passed by absolute path and uses paths relative to the project dir
  (`../01-hdl/...`).
- **Pins bind to Clash port names.** `clk → PIN_R20` (3.3-V LVTTL); `sw → PIN_AC9`
  (`SW[0]`, 1.2 V, kernel select); `ledr[9:0]` → `LEDR[9:0]` and `ledg[7:0]` →
  `LEDG[7:0]`, all 2.5 V, bound index-by-index in `for` loops. Change a port name
  in `src/` and the `.tcl` must follow.
- **Timing is single-sourced from Clash.** `pwm-wave.tcl` adds the generated
  `topEntity.sdc` as the `SDC_FILE`; no hand-written SDC.
- **Device string is `5CGXFC5C6F27C7`** — drop the trailing `N`, or `quartus_map`
  errors "Part name … is illegal".
- **`.sof` is volatile** (SRAM config); the serial-flash `.pof` path is out of scope.

## Clash notes (pwm-wave specifics)

- **`Vec n Bit` ports render as packed buses.** `topEntity` exposes `ledr :: Vec
  10 Bit` and `ledg :: Vec 8 Bit`; Clash renders these as `ledr[9:0]`/`ledg[7:0]`
  (verified in the generated Verilog). **If a future change makes a port render
  unpacked**, expose that port as `BitVector n` (via `pack`/`v2bv`) and keep `Vec`
  inside. The pins bind index-by-index either way.
  - **Expected warning (left on purpose).** `makeTopEntity` emits `[GHC-39584]
    "Backtracked when constructing Clash.Sized.Vector.Vec (Type appears
    recursive)"` for the `ledr`/`ledg` ports: `Vec` is a recursive GADT, so its
    type-walker backtracks (and treats the port as one packed bus — exactly what we
    want). It's harmless (the ports are correct) and isn't a `-W` flag, so `-Wno-`
    can't silence it; the only way to remove it is to expose the ports as the
    non-recursive `BitVector n` + `v2bv`. We keep `Vec n Bit` ports (the teaching
    point) and accept the cosmetic warning.
- **One carrier, both banks.** `pwmVec` returns `(leds, endOfPeriod)`. `waveLeds`
  concatenates `dutyR ++ dutyG` into a `Vec 18`, runs **one** `pwmVec`, and
  `splitAtI`s the LED bits back into the `10` + `8` banks — a single 16-bit
  carrier for all 18 LEDs. Don't instantiate per-bank (or per-lane) carriers; the
  shared carrier is the whole point of the vectorized core.
- **The clocked circuit is a constrained helper.** `topEntity` is
  `withClockResetEnable clk noReset enableGen waveLeds`, where `waveLeds`
  *carries* the `HiddenClockResetEnable` constraint. A flat `where` block on
  `topEntity` puts the clocked primitives outside `withClockResetEnable`'s reach
  and fails with "unbound implicit parameters" (this bit `pwm-pattern` too).
- **No reset.** `topEntity` passes `unsafeFromActiveHigh (pure False)`, relying on
  Cyclone V power-up `init` like the siblings; Clash emits no `reset` port.
- **Two triangles, kept apart.** The `Wave` machine is the *bounce trajectory*
  (where the bump is); `triangleKernel` is the *brightness falloff* (how bright by
  distance). They are independent — don't conflate them.
- **The position register is genuinely driven → no latch.** Every `waveNext`
  branch writes a real position (never a bare `x` self-hold), so Quartus infers a
  flip-flop, not a latch (contrast `pwm-pattern`'s deliberately state-less
  `Constant`). If a top ever "works in sim but not on hardware," inspect the
  generated Verilog + the `quartus_map` report for Warning 10240, don't guess.
- **Sized-type arithmetic gotchas (both caught by tests).**
  - `triangleKernel` widens to `Unsigned 32` before the `maxBound * (kernelWidth -
    d)` multiply — the same-width 16-bit product overflows and wraps to garbage.
  - `ledDist` takes `|here - pos|` by branching on order, **not** `abs (here -
    pos)`: `abs` on `Unsigned` is a no-op and the subtraction wraps below zero.
- **Carrier rate vs. animation advance.** The PWM carrier runs at full clock speed
  (`50e6 / 2^16 ≈ 763 Hz`); only the bump *advance* is gated, by `prescale (SNat
  @PrescaleExp)` on the end-of-period tick. Don't divide the core clock — the
  carrier must stay fast or the LEDs flicker.
- **Tuning lives in `PwmWave.Wave`.** `kernelWidth` (bump width, relative to
  `ledUnit`), `PosF` (sub-LED resolution / speed), `PrescaleExp` / `posStep`
  (bounce speed). All by-eye; the tests pin *shape*, not the numbers. `posStep`
  must divide `posMax`. Brightness is linear in duty but the eye is ~gamma — a
  perceptually even falloff is the gamma kernel, selected on `SW[0]` (`Gamma.hs`;
  retune via its `2.2` exponent).
- **Gamma kernel = on-chip ROM (`PwmWave.Gamma`).** `gammaTable` is a 256-entry
  curve baked at **compile time** with `listToVecTH` (the `** 2.2` is `Double` math
  with no hardware form, so it /must/ be compile-time); `gammaLUT = asyncRomPow2
  gammaTable` reads it combinationally, and `gammaCorrect` indexes by the **top 8
  bits** of a duty. `gammaKernel = gammaCorrect . triangleKernel`, so the kernels
  share geometry; `waveLeds` computes the triangle decode once, post-`map`s
  `gammaCorrect`, and `mux`es on `SW[0]`.
  - **Quantization edge:** `gammaCorrect` rounds the top intensity bucket
    (`[65280,65535]`) up to `maxBound`; safe only because the triangle's step
    (`maxBound/kernelWidth`) skips that bucket, so `gammaKernel ≤ triangleKernel`
    holds. A pure test pins it.
  - **`asyncRom` → logic, replicated.** On this Altera part the async ROM
    synthesises to LUT/distributed logic and the 18 per-LED readers replicate it
    (fine here). An M10K block would need a *synchronous* `rom` (1-cycle latency) +
    a single shared read — out of scope.
  - **`sw` is sampled raw** (no synchroniser), like pwm-pattern; the `SW0` flip is
    glitch-free anyway because `pwmVec`'s `Vec` shadow defers it to a period
    boundary.
- The `pwm-wave.cabal` `common-options` come from orangecrab — don't trim them.
  No `mtl` dependency (no `State`/`mealyS` here, unlike `pwm-pattern`).

## Tests

`stack test` runs the tasty suite (pure Haskell, no FPGA): `Tests.PwmWaveCore`
(per-lane duty exactness + the `Vec` shadow latch + the eop cadence), `Tests.Wave`
(the kernel shape laws, the spatial decode — centred/symmetric/clamped — the
counter-rotation, and the position ping-pong), and `Tests.Gamma` (the gamma table,
the gamma kernel's shape, and that gamma is never brighter than the triangle and
strictly dimmer in the mids). They pin *shape* so the by-eye tunables can change
without breaking them.

## What NOT to do

- Don't add `NAME`/`PATTERN` variants — there is one top. (The moore-vs-mealy
  split belonged to `pwm-pattern`.)
- Don't swap the gamma `asyncRom` for an M10K `blockRam`/`rom`, add a runtime-
  adjustable γ, or synchronise `sw` — all YAGNI for this teaching example.
- Don't give per-bank or per-lane carriers; one shared carrier drives all 18 LEDs.
- Don't give the top a reset port (the no-reset power-up design is deliberate).
- Don't use `abs`/same-width arithmetic on `Position`/duty without considering
  wrap (see the sized-type gotchas above).
- Don't divide the core clock to slow the animation — gate the advance with the
  prescaled enable instead.
- Don't reintroduce a `Makefile`-less "stack-only" flow or `src/{hw,sim}` nesting,
  and don't collapse the staged Quartus tools into one `execute_flow`.
- Don't bump Clash off the `stack.yaml` pin without updating the `clash-prelude`
  bound in `pwm-wave.cabal`.
