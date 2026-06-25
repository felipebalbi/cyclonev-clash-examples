# pwm-pattern

Runtime-selectable **pattern generators** driving a PWM brightness on the
**Terasic Cyclone V GX Starter Kit** (C5G, `5CGXFC5C6F27C7N`). The follow-on to
`pwm`: where `pwm` held one fixed duty, here a small state machine *generates* a
time-varying duty — a steady level, or a "breathing" triangle ramp — and a slide
switch picks which one live. Laid out to match the upstream clash-starters
`orangecrab` project and the sibling `blinky` / `pwm` examples.

The point of the example is to build the **same** generators **two ways** — once
with Clash's `moore`, once with `mealyS` (the `State` monad) — and prove the two
spellings produce a bit-identical waveform. The two constructions are the two
top entities, selected with `NAME` (default `PwmMoore`):

| `NAME` | Construction | Driver |
|---|---|---|
| `PwmMoore` | Moore machine (`Clash.Prelude.moore`) | `runMoore` |
| `PwmMealy` | Mealy machine (`Clash.Prelude.mealyS`, `State` monad) | `runMealy` |

Both expose the same ports (`clk`, `sw`, `led`) and differ by exactly one word —
`runMoore` vs `runMealy` — which is the whole teaching payoff.

## Moore vs. Mealy: two spellings of one machine

A pattern generator is a tiny state machine: a state, a transition, and a duty
decoder. The two constructions express it differently:

| | Moore (`PwmMoore`) | Mealy (`PwmMealy`) |
|---|---|---|
| Clash primitive | `moore transition decode s0` | `mealyS step s0` |
| transition | `next :: a -> a` (pure) | inside `step`, via `State` |
| output | `duty :: a -> Unsigned DutyW` (pure) | inside `step`, the return value |
| pattern method(s) | `next` + `duty` | `step :: Bool -> State a (Unsigned DutyW)` |

Each pattern type (`Constant`, `Triangle`) carries **both** a `PatGenMoore` and a
`PatGenMealy` instance — genuinely re-authored, not one wrapping the other. They
are written to behave identically: `step` returns the **pre-update** duty (the
current state's), so `mealyS` presents the same value on the same cycle as
`moore`. The tasty suite's `Equivalence` group asserts
`runMoore (initial :: Triangle) ≡ runMealy (initial :: Triangle)` cycle-for-cycle
(including under an intermittent advance tick), so the claim is checked, not just
asserted in prose.

> In a real design you would pick one construction and move on; building both is
> purely to compare them. `moore` keeps the transition and decode as two ordinary
> functions (easy to read and unit-test in isolation); `mealyS` folds them into
> one `State` action (more compact when the transition has real logic, as in
> `Triangle`). Neither is "better" — they synthesise to equivalent hardware.

## Patterns

| Pattern | `sw` | What it does |
|---|---|---|
| `Constant` | `0` (low) | A fixed 75 % duty — the `pwm` example's steady brightness, reached through the generator framework. |
| `Triangle` | `1` (high) | A level that ramps up and down, dimming the LED smoothly in and out (~2.7 s per breath). |

Both run in parallel inside each top; `sw` (`SW[0]`) just `mux`es which duty
reaches the PWM core, so one bitstream shows both — flip the switch to compare.

## How it fits together

```
50 MHz (single Dom50 domain — no PLL, no divided clock)
  │
  ▼
PwmCore.pwm ── free-running counter, full speed ──► compare vs shadow duty ──► led   (~763 Hz carrier, flicker-free)
  │
  └─ counter wrap ──► end-of-period tick ──► prescale ÷4 ──► pattern-advance enable
                                                               │
                                            runMoore/runMealy steps the selected pattern ──► duty
                                                               │
                                          shadow register latches the new duty at the period boundary
```

- **One clock, an *enable* for the animation.** The carrier must stay fast
  (`50e6 / 2^16 ≈ 763 Hz`) so the eye sees steady brightness; the pattern must
  step *slowly* so the breath is visible. So the core runs full-speed and only
  the pattern advance is gated by a prescaled tick (`PrescaleExp = 2`, ÷4) — never
  a divided clock.
- **Glitch-free duty changes.** `PwmCore` holds the duty in a *shadow register*
  that updates only at the period boundary, so a mid-period change (or a `sw`
  flip) can't produce a partial pulse.
- **Animation resolution ≠ PWM resolution.** `Triangle` ramps an 8-bit level
  (`LevelW`) scaled up to the 16-bit duty (`DutyW`); the narrow level is what
  makes a full sweep land at a visible ~2.7 s instead of ~86 s.

## Layout

```
pwm-pattern/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PwmMoore.hs                 top: patternLed via runMoore  + makeTopEntity
         PwmMealy.hs                 top: patternLed via runMealy  + makeTopEntity
         PwmCore.hs                  counter + comparator + duty shadow register + end-of-period tick
         PwmPattern/Domain.hs        Dom50 (50 MHz) clock domain
         PwmPattern/Pattern.hs       PatGen / PatGenMoore / PatGenMealy classes; runMoore / runMealy; prescale
         PwmPattern/Pattern/Constant.hs   the fixed-duty pattern (both spellings)
         PwmPattern/Pattern/Triangle.hs   the breathing pattern (both spellings)
  tests/ unittests.hs                tasty runner
         Tests/PwmCore.hs            shadow-register + end-of-period checks
         Tests/Pattern.hs            per-pattern checks + the moore/mealy Equivalence group
  pwm-pattern.tcl                    Quartus project script (device, pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program pipeline
```

`PwmMoore` and `PwmMealy` share `PwmCore`, the pattern modules, and the
`patternLed` wiring; only the driver (`runMoore` vs `runMealy`) differs.

## Build flow (two stages)

Identical to `blinky` / `pwm`:

1. **Clash → Verilog (stack):** `stack run clash -- $(NAME) --verilog` →
   `verilog/$(NAME).topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/$(NAME)/01-hdl/`, builds the Quartus project with `quartus_sh -t
   pwm-pattern.tcl $(NAME)` into `_build/$(NAME)/02-quartus/`, then runs
   `quartus_map → quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm` to
   program. Both tops share the same ports, so `pwm-pattern.tcl` needs no
   per-design pin logic.

## Quick start

```sh
stack build                  # first run installs GHC + compiles Clash (~10-15 min cold)
stack test                   # pure-Haskell checks incl. the moore/mealy equivalence proof

make                         # PwmMoore -> _build/PwmMoore/02-quartus/pwm-pattern.sof
make program                 # configure the C5G over the built-in USB-Blaster (volatile)

make NAME=PwmMealy           # the mealyS variant -> _build/PwmMealy/02-quartus/pwm-pattern.sof
make program NAME=PwmMealy   # ... and program it

make clean                   # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit` /
`bitstream` / `timing` (each honours `NAME=`). On the board, flip `SW[0]` to
switch between the steady (Constant) and breathing (Triangle) patterns.

## Pins

`pwm-pattern.tcl` binds the Clash port names (not the Terasic board labels) to
pin locations and I/O standards, from Terasic's `C5G_Default.qsf`. Both tops use
the same ports:

| Clash port | C5G signal | Pin | I/O standard |
|---|---|---|---|
| `clk` | `CLOCK_50_B5B` (50 MHz)     | `PIN_R20` | 3.3-V LVTTL |
| `led` | `LEDR[0]` (red LED 0)       | `PIN_F7`  | 2.5 V |
| `sw`  | `SW[0]` (pattern select)    | `PIN_AC9` | 1.2 V |

The full `LEDR[9:0]` bank and the other `SW`/`KEY` pins are carried as commented
blocks in `pwm-pattern.tcl`, ready for a multi-LED sweep or more select bits.

## Programming notes

Same as the other examples: the C5G has a **built-in USB-Blaster**, `make
program` runs `quartus_pgm -m jtag -o "p;pwm-pattern.sof"`, and the `.sof`
configures SRAM and is **lost on power cycle** (the serial-flash `.pof` path is
out of scope). See `blinky/README.md` for the cable/`jtagconfig` notes.
