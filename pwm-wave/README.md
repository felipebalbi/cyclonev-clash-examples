# pwm-wave

A brightness **wave** travelling across the two LED banks of the **Terasic
Cyclone V GX Starter Kit** (C5G, `5CGXFC5C6F27C7N`). A single glowing **bump**
ping-pongs back and forth — a Larson/KITT scanner rendered with per-LED **PWM**
brightness instead of on/off, so it *glides* rather than hops. The two banks
**counter-rotate**: when the red peak is at one end, the green peak is at the
other.

- **Red** `LEDR[9:0]`: the peak walks `0 → 9 → 0` (and repeats).
- **Green** `LEDG[7:0]`: the peak walks `7 → 0 → 7` (mirrored).

The follow-on to `pwm-pattern`. Where that example's teaching axis was *moore vs.
mealy*, here it is **vectors**: `Vec n Bit` ports and a **vectorized PWM core**
(one carrier, N independent comparators). There is a **single** top entity — no
`NAME` variants. `SW[0]` switches the brightness falloff between a linear
**triangle** and a **gamma** curve held in the repo's first on-chip ROM.

## The new ideas (vectors)

| Vector idea | Where |
|---|---|
| `Vec n Bit` output ports → packed `ledr[9:0]`/`ledg[7:0]` buses | `topEntity` |
| Vectorized PWM: **one** carrier, N comparators, a `Vec` shadow register | `PwmWave.Core.pwmVec` |
| `imap` spatial decode — one position → a `Vec` of per-LED duties | `PwmWave.Wave.bumpVec` |
| `reverse` as counter-rotation — green is red, mirrored | `PwmWave.Wave.greenDuties` |
| `++` then `splitAtI` — one carrier feeds **both** banks | `PwmWave.waveLeds` |
| compile-time gamma LUT in **on-chip ROM** (`asyncRom`), selected by `SW[0]` | `PwmWave.Gamma` |

## How it fits together

```
50 MHz (single Dom50 domain — no PLL, no divided clock)
  │
  ▼
runWave ── position ping-pongs 0 → posMax → 0 (the bounce trajectory) ──► pos
  ▲                                                                       │
  └─ prescaled end-of-period tick advances it (~3 s per full bounce)      │
                                                                          ▼
spatial decode ── per LED i:  triangleKernel (|i·ledUnit − pos|) ──► dutyR :: Vec 10
                                                                    dutyG :: Vec 8  (= reverse dutyR)
                                                                          │
                                                                  dutyR ++ dutyG  (Vec 18)
                                                                          ▼
pwmVec ── ONE 16-bit carrier (~763 Hz) · 18 comparators · Vec shadow ──► splitAtI ──► ledr[9:0], ledg[7:0]
```

`SW[0]` high inserts a per-lane `map gammaCorrect` between the decode and `pwmVec`
— same bump, gamma-mapped brightness (see *Gamma vs. triangle* below).

### The "two triangles"

Two unrelated triangles meet in the decode — don't conflate them:

- the **bounce trajectory** — `PwmWave.Wave`'s `Wave` machine, pwm-pattern's
  `Triangle` motion retargeted from a brightness *level* to a *position*. It says
  **where** the bump is.
- the **glow shape** — `triangleKernel`, a pure `distance → brightness` falloff.
  It says **how bright** each LED near the bump is.

`runWave` produces one number, `pos`; the decode turns that single position into
the two banks' duty vectors.

### One carrier, both banks

The whole point of the vectorized core is that a **single** 16-bit carrier counter
drives all 18 LEDs. `waveLeds` concatenates the red and green duty vectors into a
`Vec 18`, hands it to one `pwmVec`, and `splitAtI`s the resulting LED bits back
into the `10` + `8` banks. The carrier must run full-speed (`50e6 / 2^16 ≈
763 Hz`) so the eye sees steady brightness; only the *animation advance* is slowed
(by `prescale`), never the carrier — so the LEDs never flicker.

### Sub-LED glide

Position is **fixed-point**: `2^PosF` units per LED (`PosF = 7` → 128 units/LED).
The bump's centre moves in those sub-LED steps, and the kernel dims each LED by
its fractional distance — that is what makes the bump slide smoothly between LEDs
instead of jumping. `PosF` trades smoothness against speed; `kernelWidth` (in LED
units) sets how many LEDs glow and how sharply.

## Layout

```
pwm-wave/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PwmWave.hs                  top: topEntity (clk, sw -> ledr, ledg) + waveLeds + makeTopEntity
         PwmWave/Domain.hs           Dom50 (50 MHz) clock domain
         PwmWave/Core.hs             pwmVec — vectorized PWM (one carrier, N comparators, Vec shadow, eop)
         PwmWave/Wave.hs             triangleKernel + the Wave position machine + bumpVec/red/greenDuties + prescale
         PwmWave/Gamma.hs            gamma LUT in on-chip ROM (gammaKernel = gammaCorrect . triangleKernel)
  tests/ unittests.hs                tasty runner
         Tests/PwmWaveCore.hs        per-lane duty exactness + Vec shadow + eop cadence
         Tests/Wave.hs              kernel shape + spatial decode + counter-rotation + position ping-pong
         Tests/Gamma.hs             gamma table + kernel shape + the "gamma darkens" property
  pwm-wave.tcl                       Quartus project script (device, pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program pipeline
```

Self-contained — `pwm-wave` carries its own PWM core and waveform, like
`pwm-pattern` didn't import `pwm`.

## Build flow (two stages)

Identical to `blinky` / `pwm` / `pwm-pattern`:

1. **Clash → Verilog (stack):** `stack run clash -- PwmWave --verilog` →
   `verilog/PwmWave.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/PwmWave/01-hdl/`, builds the Quartus project with `quartus_sh -t
   pwm-wave.tcl PwmWave` into `_build/PwmWave/02-quartus/`, then runs `quartus_map
   → quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm` to program.

## Quick start

```sh
stack build                  # first run installs GHC + compiles Clash (~10-15 min cold)
stack test                   # pure-Haskell checks (carrier, kernel, decode, counter-rotation, bounce)

make                         # PwmWave -> _build/PwmWave/02-quartus/pwm-wave.sof
make program                 # configure the C5G over the built-in USB-Blaster (volatile)

make clean                   # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit` /
`bitstream` / `timing`.

### Tuning by eye

All animation parameters live in `src/PwmWave/Wave.hs` and are tunable on
hardware (the tests pin *shape*, not numbers):

- `kernelWidth` — bump width, in LED units. The neighbour brightness fraction is
  `1 - ledUnit/kernelWidth`; narrow it toward `ledUnit` (but keep it **strictly
  greater**, or the neighbours blink dark when the peak lands on an LED) for a
  sharper dot. Note PWM duty is *linear* but the eye is ~gamma, so a 33%-duty
  neighbour still looks bright — flip `SW[0]` to the gamma kernel for the real,
  perceptual fix.
- `PosF` — sub-LED resolution: smoothness vs. animation speed.
- `PrescaleExp` / `posStep` — bounce speed (`PrescaleExp = 0`, `posStep = 1`,
  `PosF = 7` lands a full bounce at ~3 s).
- γ — the gamma exponent (`2.2`) lives in `src/PwmWave/Gamma.hs`; edit it to
  reshape the gamma curve.

## Pins

`pwm-wave.tcl` binds the Clash port names (not the Terasic board labels) to pin
locations and I/O standards, from Terasic's `C5G_Default.qsf`. The `Vec n Bit`
ports render as packed buses, so each index binds to one pin:

| Clash port | C5G signal | Pin | I/O standard |
|---|---|---|---|
| `clk` | `CLOCK_50_B5B` (50 MHz) | `PIN_R20` | 3.3-V LVTTL |
| `ledr[0..9]` | `LEDR[9:0]` (red) | `F7 F6 G6 G7 J8 J7 K10 K8 H7 J10` | 2.5 V |
| `ledg[0..7]` | `LEDG[7:0]` (green) | `L7 K6 D8 E9 A5 B6 H8 H9` | 2.5 V |
| `sw` | `SW[0]` (kernel select) | `PIN_AC9` | 1.2 V |

Timing is single-sourced: the tcl adds Clash's generated `topEntity.sdc` (a
`create_clock` at the 20 ns / 50 MHz `Dom50` period); there is no hand-written
SDC. There is no reset port — the registers rely on the Cyclone V power-up `init`.

## Programming notes

Same as the other examples: the C5G has a **built-in USB-Blaster**, `make
program` runs `quartus_pgm -m jtag -o "p;pwm-wave.sof"`, and the `.sof` configures
SRAM and is **lost on power cycle** (the serial-flash `.pof` path is out of
scope). See `blinky/README.md` for the cable/`jtagconfig` notes.

## Gamma vs. triangle (`SW[0]`)

`triangleKernel` falls off linearly in *duty*, but LED brightness perception is
roughly gamma — so a linear bump's neighbours look nearly as bright as its peak.
`SW[0]` re-maps the falloff to fix that:

- **`SW[0]` low** — the linear **triangle** (v1).
- **`SW[0]` high** — **gamma**: the same bump geometry, brightness re-mapped so the
  falloff *looks* even (a clean glowing dot).

The gamma curve is the repo's **first on-chip ROM**. A 256-entry table is baked at
compile time (`listToVecTH`, `table[i] = (i/255)^2.2 · maxBound`) and read by a
combinational `asyncRom`; `gammaKernel = gammaCorrect . triangleKernel`, so the two
kernels share geometry and differ only in brightness mapping. The decode computes
the triangle once and gamma is a per-lane `map gammaCorrect`, `mux`ed on `SW[0]`.
The flip is glitch-free (the `Vec` shadow defers it to a period boundary), and `sw`
is sampled raw — a metastable sample at worst delays the switch by one ~763 Hz
period.

On this Altera part the async ROM synthesises to logic (not an M10K block) and its
18 per-LED readers replicate it — visible in the `quartus_map` report. Retune the
curve by editing the `2.2` exponent in `src/PwmWave/Gamma.hs`.
