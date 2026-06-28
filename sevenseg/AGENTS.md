# AGENTS.md — sevenseg

A **hex odometer** on the four seven-segment displays of the Terasic Cyclone V GX
Starter Kit (C5G), laid out to match the upstream clash-starters `orangecrab`
project and the sibling `blinky` / `pwm` / `pwm-pattern` / `pwm-wave` examples. A
free-running counter, divided to a visible rate, shows its 16-bit value as
`0000`–`FFFF` across `HEX3`–`HEX0`. See `README.md` for the human-facing
walkthrough.

The teaching axis is a pure **combinational decoder** (hex nibble → seven
active-low segments) plus composing a word into four **independently driven**
digits — not PWM, not a ROM. Self-contained.

## Cross-project deps

None. Self-contained, like the siblings. Pin choices and I/O standards are read
from Terasic's `C5G_Default.qsf`; nothing is copied — `sevenseg.tcl` is written
fresh against the Clash port names (`clk`, `hex0`–`hex3`).

## Source layout (orangecrab-style)

```
sevenseg/
  bin/   Clash.hs / Clashi.hs        thin Clash.Main wrappers (clash, clashi exes)
  src/   SevenSeg.hs                 top: topEntity + displays + makeTopEntity
         SevenSeg/Domain.hs          Dom50 clock domain
         SevenSeg/Decode.hs          hexToSeg + nibbles + display + segToBus + displayPorts
         SevenSeg/Odometer.hs        odometerValue (high slice) + odometer (clocked counter)
  tests/ unittests.hs               tasty runner
         Tests/Decode.hs             font truth table + structure + nibbles/display + order + alignment
         Tests/Odometer.hs           slice law + cadence
  sevenseg.tcl                       Quartus project script (device, per-digit pins, SDC)
  Makefile  build.cfg               Clash -> Quartus -> program
```

No `src/hw`, `src/sim`, or `src/build` nesting — synthesizable code, the domain,
and tests split by the top-level `src/` vs `tests/` dirs, like orangecrab.

## One top, no variants

A **single** `topEntity` (`SevenSeg`). `NAME` survives in the Makefile only for
parity with the sibling build machinery (and to key `_build/$(NAME)/`); it is
`SevenSeg` and is forwarded to (but unused by) `sevenseg.tcl`.

## Build flow (two stages)

Identical to the siblings:

1. **Clash → Verilog (stack):** `stack run clash -- SevenSeg --verilog` →
   `verilog/SevenSeg.topEntity/topEntity.v` (+ `topEntity.sdc`).
2. **Gates → board (make):** stage HDL into `_build/SevenSeg/01-hdl/`, build the
   Quartus project with `quartus_sh -t sevenseg.tcl SevenSeg` into
   `_build/SevenSeg/02-quartus/`, then `quartus_map → quartus_fit → quartus_asm →
   quartus_sta`, and `quartus_pgm`. Tool paths from `build.cfg`.

## Quartus specifics (same as the siblings, except the I/O split)

- **TCL builds the project; the Makefile runs the stages.** `sevenseg.tcl` (run
  via `quartus_sh -t sevenseg.tcl SevenSeg`) only writes the `.qsf`. Its
  `project_new` name is `sevenseg`, matching the Makefile's `QPROJ` so the
  discrete stages (`quartus_map sevenseg`, …) find the revision.
- **Recipes `cd $(QDIR)` first.** Quartus CLI tools are cwd-oriented; the `.tcl`
  is passed by absolute path and uses paths relative to the project dir
  (`../01-hdl/...`).
- **The four digits are NOT on one I/O standard.** This is the only real
  divergence from `pwm-wave.tcl`: `HEX0`/`HEX1` are **1.2 V**, `HEX2`/`HEX3` are
  **3.3-V LVTTL**. So `sevenseg.tcl` sets each digit's standard individually (a
  `bind_hex {port pins iostd}` proc), rather than looping one standard over a
  whole bank. `clk → PIN_R20` (3.3-V LVTTL). Pin-list index `i` = segment `i`
  (`a..g`), matching C5G `HEX_i[i]`. Change a port name in `src/` and the `.tcl`
  must follow.
- **Timing is single-sourced from Clash.** `sevenseg.tcl` adds the generated
  `topEntity.sdc` as the `SDC_FILE`; no hand-written SDC.
- **Device string is `5CGXFC5C6F27C7`** — drop the trailing `N`, or `quartus_map`
  errors "Part name … is illegal".
- **`.sof` is volatile** (SRAM config); the serial-flash `.pof` path is out of scope.

## Clash notes (sevenseg specifics)

- **`BitVector 7` ports, not `Vec 7 Bit`.** Each digit leaves as `BitVector 7`
  (rendering as packed `hex_i[6:0]`), built from an internal `Vec 7 Bit`. This
  avoids the GHC-39584 `Vec`-recursive `makeTopEntity` warning that `pwm-wave`'s
  `Vec n Bit` ports trip. The pins bind index-by-index either way.
- **Bit alignment: `segToBus = v2bv . reverse`.** Clash's `v2bv` puts the `Vec`
  head at the MSB, so a bare `v2bv` would mirror the segments (segment `a` → bit
  6). The `reverse` lands segment `a` (`Vec` index 0) at bus bit 0, so
  `hex_i[k]` = segment `k` = C5G `HEX_i[k]`. `Tests.Decode`'s alignment case
  (one-hot in → single bit out) exists precisely to catch a missing/doubled
  `reverse`; don't drop it.
- **Active-low font.** A segment is lit when its bit is `0`; `8` is all-zero,
  blank is all-ones. The font is a `Vec 16 (Vec 7 Bit)` LUT indexed by the
  nibble (`segTable !! d`) — **indexing, not literal pattern matching**, so the
  coverage checker stays happy (numeric literal patterns over `Unsigned 4` are
  never seen as exhaustive). `Tests.Decode` pins the full `0`–`F` truth table.
- **Digit order: MSD on `HEX3`.** `nibbles`/`display` are MSD-first (index 0 =
  top nibble); `displayPorts = reverse . map segToBus . display` flips to port
  order (index 0 = `hex0`), so `0x1234` reads `1234` with `hex3=1`. A test pins
  it — don't "simplify" the `reverse` away.
- **`displays` indexes the unbundled `Vec`, it doesn't destructure it.**
  `busAt i = ports !! i` over `ports = unbundle (displayPorts <$> odometer)`.
  Destructuring a `Vec 4` with a `:>`/`Nil` pattern trips
  `-Wincomplete-uni-patterns` (the length GADT isn't resolved by the coverage
  checker), so we index instead — the same "index, don't pattern-match" lesson as
  the font LUT.
- **`odometerValue` is polymorphic in the divider; `DivBits` is the concrete
  one.** `odometerValue :: forall k. KnownNat k => Unsigned (16 + k) -> Unsigned
  16` is the pure high-slice (tested at a small `k`); the clocked `odometer`
  instantiates `k = DivBits` (default 23). `DivBits` is a by-eye rate knob like
  `blinky`'s divider; the tests pin the slice *relationship*, not the rate.
- **No reset.** `topEntity` passes `unsafeFromActiveHigh (pure False)`, relying on
  Cyclone V power-up `init` like the siblings; Clash emits no `reset` port. The
  clocked circuit lives in the constrained helper `displays`
  (`HiddenClockResetEnable`); a flat `where` on `topEntity` fails with "unbound
  implicit parameters".
- **The decoder is logic, not memory.** A 16×7 LUT minimizes to a handful of
  ALM/LUTs; `quartus_fit` reports `Total block memory bits : 0`. The ~40
  registers are the odometer counter (the decode is combinational). Don't reach
  for `asyncRom`/`blockRam` here — it's far too small to want a memory block.
- The `sevenseg.cabal` `common-options` come from orangecrab — don't trim them.
  No `mtl` dependency (no `State`/`mealyS` here).

## Tests

`stack test` runs the tasty suite (pure Haskell, no FPGA): `Tests.Decode` (the
full `0`–`F` active-low font truth table, the structural guards, `nibbles`/
`display`, the MSD-on-`hex3` digit order, and the `segToBus` bus alignment) and
`Tests.Odometer` (the high-slice law and the odometer cadence — one `HEX0` tick
per `2^k` counts, 16× between adjacent digits). The odometer tests use a small
`k` and exercise the pure `odometerValue`, so no signal sampling is needed.

## What NOT to do

- **Don't add TDM / digit multiplexing.** The C5G's four digits are
  independently driven (28 dedicated segment pins); multiplexing them in logic is
  pointless. Real TDM belongs to a later keypad-matrix / multiplexed-display
  example where the sharing is genuine.
- **Don't add firmware debounce** — there are no buttons here, and the C5G keys
  are RC-debounced in hardware anyway.
- **Don't give the top a reset port** (the no-reset power-up design is deliberate).
- **Don't add a decimal point** — each C5G `HEX_i` is `[6:0]`, 7 segments, no DP
  pin. No leading-zero blanking, no runtime value-source select either — all YAGNI.
- Don't swap the font LUT for an `asyncRom`/`blockRam`, or destructure the
  unbundled `Vec` with a `:>` pattern (use `!!`).
- Don't hand-write SDC (single-source from Clash's `topEntity.sdc`), and don't
  bump Clash off the `stack.yaml` pin without updating the `clash-prelude` bound.
- Don't reintroduce `src/{hw,sim}` nesting or collapse the staged Quartus tools
  into one `execute_flow`.
