# pushbutton

A **pushbutton-toggled LED** on the **Terasic Cyclone V GX Starter Kit** (C5G,
`5CGXFC5C6F27C7N`). Press `KEY0` and `LEDR[0]` flips; it holds until the next
press. One button, one LED — the smallest honest example of reading an
asynchronous input.

The follow-on to `sevenseg`. Where that example's teaching axis was a pure
combinational decoder, here it is three tiny **clocked** primitives that recur
everywhere downstream: a 2-FF input **synchronizer**, a rising-edge **detector**,
and a **toggle** flip-flop. There is no PWM, no ROM, no time-division
multiplexing, and — like the siblings — **no reset**.

## The new ideas

| Idea | Where |
|---|---|
| 2-FF metastability **synchronizer** for an async pin | `PushButton.Button.synchronize` |
| **Edge detector** — one-cycle pulse on a `False→True` transition | `PushButton.Button.risingEdge` |
| **Toggle (T) flip-flop** — flip on a pulse, hold otherwise | `PushButton.Button.toggleOn` |
| **Active-low** input — a press is a *falling* edge of the pin | `PushButton.toggleLed` (the `== low` invert) |
| Composing clocked stages as one pipeline | `PushButton.toggleLed` |

## Synchronize ≠ debounce

The single most important point of this example. **Debounce** and
**synchronization** are different problems:

- **Debounce** cleans the mechanical chatter of a switch contact. The C5G's
  `KEY` buttons are **RC-filtered in hardware**, so they don't bounce — no
  firmware debounce is needed.
- **Synchronization** hardens an *asynchronous* signal against metastability. The
  button is still async to the 50 MHz `Dom50` clock, so a press can land too
  close to a clock edge and drive a flip-flop metastable. The RC filter does
  **nothing** about that.

So the board solves the first problem and the gateware must still solve the
second: a clean-but-async signal still needs a **2-FF synchronizer** before any
edge logic. Don't let "it's already debounced" talk you out of `synchronize`.
This is the same machinery `BlinkyWithReset` uses to route KEY0 to a reset — here
it routes the button to *data* instead.

## How it fits together

```
50 MHz (single Dom50 domain — no PLL, no divided clock, no reset)
  │
key0 :: Bit   (async, active-low, RC-debounced)
  │  synchronize     two cascaded registers — metastability hardener
  ▼
  │  == low          active-low pin → pressed = True  (a press is a falling edge of the pin)
  ▼
pressed :: Bool
  │  risingEdge      curr && not prev — one-cycle pulse per new press
  ▼
pulse :: Bool
  │  toggleOn        T flip-flop, seeded low
  ▼
led :: Bit → LEDR[0]
```

### Active-low → a press is a falling edge

`KEY0` reads **high when released, low when pressed**. So a press is a `1→0`
*falling* edge of the pin. Inverting early (`== low`) turns "pressed" into a plain
`True`, so the edge detector reads a normal **rising** edge — and the polarity is
pinned by a test, not assumed.

### No reset

Like `blinky` / `sevenseg`, the toggle flip-flop powers up `low` from the
Cyclone V `init` value, so there's no reset port: `topEntity` hands Clash a
permanently de-asserted reset and Clash emits no `reset` pin. If you want a clear
button, synchronize a *separate* KEY into a `Reset` the way `BlinkyWithReset`
does — don't drive the LED through a raw reset net.

## Layout

```
pushbutton/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   PushButton.hs               top: topEntity (clk, key0 -> led) + toggleLed + makeTopEntity
         PushButton/Domain.hs        Dom50 (50 MHz) clock domain
         PushButton/Button.hs        synchronize + risingEdge + toggleOn (the three primitives)
  tests/ unittests.hs                tasty runner
         Tests/Button.hs             each primitive's law, the active-low polarity, and a capstone
  pushbutton.tcl                     Quartus project script (device, clk/key0/led pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program pipeline
```

Self-contained, like the siblings — the synchronizer reuse is by *pattern*, not
shared code (`BlinkyWithReset` does the same 2-FF trick for a reset).

## Build flow (two stages)

Identical to `blinky` / `pwm` / `sevenseg`:

1. **Clash → Verilog (stack):** `stack run clash -- PushButton --verilog` →
   `verilog/PushButton.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/PushButton/01-hdl/`, builds the Quartus project with `quartus_sh -t
   pushbutton.tcl PushButton` into `_build/PushButton/02-quartus/`, then runs
   `quartus_map → quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm` to
   program.

## Quick start

```sh
stack build                  # first run installs GHC + compiles Clash (~10-15 min cold)
stack test                   # pure-Haskell checks (synchronizer, edge, toggle, polarity, capstone)

make                         # PushButton -> _build/PushButton/02-quartus/pushbutton.sof
make program                 # configure the C5G over the built-in USB-Blaster (volatile)

make clean                   # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit` /
`bitstream` / `timing`.

## Pins

`pushbutton.tcl` binds the Clash port names (not the Terasic board labels) to pin
locations and I/O standards, from Terasic's `C5G_Default.qsf`. Note the three
ports are on **three different I/O standards** (mixed-voltage banks):

| Clash port | C5G signal | I/O standard | Pin |
|---|---|---|---|
| `clk`  | `CLOCK_50_B5B` (50 MHz) | 3.3-V LVTTL | `R20` |
| `key0` | `KEY[0]` (active-low) | **1.2 V** | `P11` |
| `led`  | `LEDR[0]` (red) | **2.5 V** | `F7` |

Timing is single-sourced: the `.tcl` adds Clash's generated `topEntity.sdc` (a
`create_clock` at the 20 ns / 50 MHz `Dom50` period); there is no hand-written
SDC. There is no reset port.

## A note on the circuit in hardware

The three primitives are pure flip-flops, not latches: every cycle each register
takes a real value (the `register`/`complement` style), so `quartus_map` infers
five FFs (two for the synchronizer, one for the edge detector's `prev`, one for
the toggle, plus the de-glitched output) and **zero** latches. If a design like
this ever "works in sim but not on hardware," read the generated Verilog and the
`quartus_map` report (Warning 10240 = inferred latch) rather than guessing.

## What comes after

The edge detector + synchronizer here is the prerequisite micro-skill for the
next bring-up — **UART** over the C5G's on-board USB-UART, whose receiver reuses
this synchronizer (RX line) and edge detector (start-bit fall), adding a baud
generator, oversampling, a shift register, and framing. A keypad-matrix scan
later reuses the same per-row edge detection.

## Programming notes

Same as the other examples: the C5G has a **built-in USB-Blaster**, `make
program` runs `quartus_pgm -m jtag -o "p;pushbutton.sof"`, and the `.sof`
configures SRAM and is **lost on power cycle** (the serial-flash `.pof` path is
out of scope). See `blinky/README.md` for the cable/`jtagconfig` notes.
