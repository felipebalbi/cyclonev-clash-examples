# sevenseg

A **hex odometer** on the four on-board seven-segment displays of the **Terasic
Cyclone V GX Starter Kit** (C5G, `5CGXFC5C6F27C7N`). A free-running counter,
divided to a visible rate, shows its 16-bit value as `0000`–`FFFF` across
`HEX3 HEX2 HEX1 HEX0` (left → right). `HEX0` spins fastest; each digit to its
left advances 16× slower — a real odometer.

The follow-on to `pwm-wave`. Where that example's teaching axis was the
*vectorized PWM core*, here it is a pure **combinational decoder**: a hex
nibble → seven **active-low** segments, and composing a word into four
**independently driven** digits. There is no PWM, no ROM, no reset — and
deliberately **no time-division multiplexing** (see below).

## The new ideas

| Idea | Where |
|---|---|
| Pure combinational hex→segment **decoder** (a LUT indexed by the nibble) | `SevenSeg.Decode.hexToSeg` |
| **Active-low** convention — a segment lights when its bit is `0` | `hexToSeg` + its test |
| Word → four digits by reinterpreting bits (`bitCoerce`), no arithmetic | `SevenSeg.Decode.nibbles` |
| `map` the decoder over the digit vector | `SevenSeg.Decode.display` |
| `Vec 7 Bit` → `BitVector 7` at the port, **bus bit k = segment k** | `SevenSeg.Decode.segToBus` |
| One wide counter; the visible value is its **high 16-bit slice** | `SevenSeg.Odometer` |

## Why no multiplexing?

Many 7-segment tutorials (and *Retrocomputing with Clash* ch. 5) **time-division
multiplex** the displays: the digits share one set of segment lines, and you
flash them one at a time fast enough that the eye fuses them. **The C5G doesn't
share** — each of `HEX0`–`HEX3` has its own seven segment pins (28 in total). So
multiplexing here would be pointless logic; every digit is driven directly and
continuously. (TDM has a real home later, in a keypad-matrix scan where the
sharing is genuine.)

## How it fits together

```
50 MHz (single Dom50 domain — no PLL, no divided clock, no reset)
  │
  ▼
counter :: Unsigned (16 + DivBits)   register 0 (counter + 1)   ── one free-running wide counter
  │  odometerValue (take the high 16 bits — a combinational slice)
  ▼
value :: Unsigned 16                 ── HEX0 = low nibble, spins fastest
  │  nibbles (= bitCoerce ; MSD-first)
  ▼
Vec 4 (Unsigned 4)   <n3,n2,n1,n0>   value 0x1234 → <0x1,0x2,0x3,0x4>
  │  map hexToSeg     (active-low decoder, per nibble)
  ▼
Vec 4 (Vec 7 Bit)
  │  map segToBus + reverse → port order
  ▼
hex3 hex2 hex1 hex0 :: BitVector 7   (active-low, packed [6:0])
```

### Active-low

A segment is lit when its bit is **`0`** (the common-anode wiring sinks current
through the FPGA pin). So `8` — every segment on — is the all-zero pattern
`0b0000000`, and a blank digit would be all-ones. The decoder's test pins the
full `0`–`F` truth table so the font is checked, not assumed.

### Digit order (MSD on HEX3)

`HEX3` is the leftmost display, so the **most-significant** nibble goes there:
`value = 0x1234` reads **`1234`** with `hex3=1 … hex0=4`. `nibbles` is MSD-first
(index 0 = top nibble); `displayPorts` then `reverse`s it into port order
(index 0 = `hex0`). A test pins this so the number never shows up mirrored.

### Bit alignment

Each digit leaves the chip as a `BitVector 7` whose **bit `k` is segment `k`**
(`hex_i[k]` ↔ C5G `HEX_i[k]`). Clash's `v2bv` puts a `Vec`'s head at the MSB, so
`segToBus = v2bv . reverse` lands segment `a` (index 0) at bit 0. A test pins the
alignment; the `.tcl` pin list is in the same `a..g` order, so the binding is
index-for-index.

### One counter, four digits

The 16-bit odometer value is just the **high 16 bits** of one wide
`Unsigned (16 + DivBits)` counter — the same "a counter's high bits are a slower
count" trick as `blinky`. `HEX0` (the low nibble of the slice) advances at
`50e6 / 2^DivBits`; each digit to its left is 16× slower. Only the *visible rate*
is divided; there's no second counter.

## Layout

```
sevenseg/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   SevenSeg.hs                 top: topEntity (clk -> hex0..hex3) + displays + makeTopEntity
         SevenSeg/Domain.hs          Dom50 (50 MHz) clock domain
         SevenSeg/Decode.hs          hexToSeg (active-low font) + nibbles + display + segToBus + displayPorts
         SevenSeg/Odometer.hs        wide counter + odometerValue (high slice)
  tests/ unittests.hs                tasty runner
         Tests/Decode.hs             font truth table + structure + nibbles/display + digit order + bus alignment
         Tests/Odometer.hs           the high-slice law + odometer cadence (16x ratio)
  sevenseg.tcl                       Quartus project script (device, per-digit pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program pipeline
```

Self-contained, like the siblings — `sevenseg` carries its own decoder and time
base.

## Build flow (two stages)

Identical to `blinky` / `pwm` / `pwm-pattern` / `pwm-wave`:

1. **Clash → Verilog (stack):** `stack run clash -- SevenSeg --verilog` →
   `verilog/SevenSeg.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Verilog → bitstream → board (make):** the `Makefile` stages the HDL into
   `_build/SevenSeg/01-hdl/`, builds the Quartus project with `quartus_sh -t
   sevenseg.tcl SevenSeg` into `_build/SevenSeg/02-quartus/`, then runs
   `quartus_map → quartus_fit → quartus_asm → quartus_sta`, and `quartus_pgm` to
   program.

## Quick start

```sh
stack build                  # first run installs GHC + compiles Clash (~10-15 min cold)
stack test                   # pure-Haskell checks (font, decode, digit order, bus alignment, odometer)

make                         # SevenSeg -> _build/SevenSeg/02-quartus/sevenseg.sof
make program                 # configure the C5G over the built-in USB-Blaster (volatile)

make clean                   # remove _build/ and verilog/
```

`make` stops at the `.sof`; individual stages: `make project` / `synth` / `fit` /
`bitstream` / `timing`.

### Tuning

`DivBits` in `src/SevenSeg/Odometer.hs` sets the visible rate (the value advances
at `50e6 / 2^DivBits`). The default `23` lands `HEX0` at ≈ 6 Hz — fast enough to
look like spinning, slow enough to read. Raise it to slow the odometer; the tests
pin the slice *relationship*, not the number, so they don't change.

## Pins

`sevenseg.tcl` binds the Clash port names (not the Terasic board labels) to pin
locations and I/O standards, from Terasic's `C5G_Default.qsf`. The `BitVector 7`
ports render as packed `[6:0]` buses, so each index binds to one pin
(`hex_i[k]` ↔ segment `k` ↔ C5G `HEX_i[k]`):

| Clash port | C5G signal | I/O standard | Pins (seg `a … g`) |
|---|---|---|---|
| `clk`  | `CLOCK_50_B5B` (50 MHz) | 3.3-V LVTTL | `R20` |
| `hex0` | `HEX0[6:0]` | **1.2 V**       | `V19 V18 V17 W18 Y20 Y19 Y18` |
| `hex1` | `HEX1[6:0]` | **1.2 V**       | `AA18 AD26 AB19 AE26 AE25 AC19 AF24` |
| `hex2` | `HEX2[6:0]` | **3.3-V LVTTL** | `AD7 AD6 U20 V22 V20 W21 W20` |
| `hex3` | `HEX3[6:0]` | **3.3-V LVTTL** | `Y24 Y23 AA23 AA22 AC24 AC23 AC22` |

Note the displays are **not** on a uniform I/O standard — `HEX0`/`HEX1` are
1.2 V, `HEX2`/`HEX3` are 3.3-V LVTTL — so the `.tcl` sets each digit's standard
individually (a `bind_hex` proc), unlike `pwm-wave.tcl`'s single-standard loops.

Timing is single-sourced: the `.tcl` adds Clash's generated `topEntity.sdc` (a
`create_clock` at the 20 ns / 50 MHz `Dom50` period); there is no hand-written
SDC. There is no reset port — the registers rely on the Cyclone V power-up
`init`.

## A note on the decoder in hardware

The decoder reads like a 16-entry lookup table in Haskell, but it does **not**
stay a "stored table." Clash lowers it to a combinational `case`, and Quartus
minimizes that into per-output boolean logic and maps it onto the device's LUTs
(an ALM is built from fracturable 6-input LUTs — a LUT *is* a truth table in
silicon). A 4-input → 7-output function is a handful of LUTs and **zero memory
bits**: the `quartus_fit` report shows `Total block memory bits : 0`, with the
~40 registers being the odometer counter, not the decoder. On a LUT FPGA the
table and a Karnaugh-minimized boolean equation converge to the same gates.

## Programming notes

Same as the other examples: the C5G has a **built-in USB-Blaster**, `make
program` runs `quartus_pgm -m jtag -o "p;sevenseg.sof"`, and the `.sof` configures
SRAM and is **lost on power cycle** (the serial-flash `.pof` path is out of
scope). See `blinky/README.md` for the cable/`jtagconfig` notes.
