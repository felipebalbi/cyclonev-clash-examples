# cyclonev-clash-examples

Bottom-up [Clash](https://clash-lang.org/) (Haskell HDL) bring-up examples for
the [Terasic Cyclone V GX Starter Kit](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&No=830)
(C5G, Intel/Altera `5CGXFC5C6F27C7N`). The Quartus sibling of
`icebreaker-clash-examples`: same Haskell/Clash front end, but the
gates → board backend is the **Intel/Altera Quartus Prime Lite** toolchain
(`quartus_map → quartus_fit → quartus_asm → quartus_sta → quartus_pgm`) instead
of the open-source `yosys → nextpnr → icepack → iceprog` flow.

Each example is laid out to match the upstream
[clash-starters](https://github.com/clash-lang/clash-starters) projects
(`bin/`, `src/`, `tests/` + a `Makefile`), so what you learn here transfers
straight to other Clash projects.

## Examples

| Example | What it is |
|---|---|
| [`blinky/`](blinky/) | Counter-divider drives an on-board LED. The "hello world" smoke test for the whole Clash → Quartus → board toolchain. Two tops: `Blinky` (free-runs) and `BlinkyWithReset` (held in reset by KEY0). |
| [`pwm/`](pwm/) | Counter+comparator emits a duty-cycled output; a ramped duty makes `LEDR[0]` "breathe". The follow-on to `blinky`: where blinky toggled an LED, PWM dims one. |

## Toolchain

- [`stack`](https://docs.haskellstack.org/) — fetches GHC + Clash, builds the
  design, runs tests, and generates Verilog (`stack run clash -- <Top> --verilog`).
- **Quartus Prime Lite** (`quartus_sh`, `quartus_map`, `quartus_fit`,
  `quartus_asm`, `quartus_sta`, `quartus_pgm`) — project setup (TCL), synthesis,
  place & route, bitstream assembly, timing analysis, and JTAG programming over
  the board's built-in USB-Blaster. Tested with Quartus 25.1std Lite.

## Quick start

```sh
cd blinky
stack build      # first run installs GHC + compiles Clash (~10-15 min cold)
stack test       # run the example's test-suite
make             # Clash -> Verilog -> Quartus -> blinky.sof
make program     # program the C5G over the built-in USB-Blaster (volatile)
```

`make` stops at the `.sof` bitstream; programming is the explicit `make program`
step. See each example's `README.md` for details and `AGENTS.md` for the
conventions that keep the examples consistent.

## License

[MIT](LICENSE) © 2026 Felipe Balbi.
