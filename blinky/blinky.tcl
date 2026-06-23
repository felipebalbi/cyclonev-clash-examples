# Quartus project-generation script for the C5G blinky examples.
#
# Serves BOTH top entities (Blinky and BlinkyWithReset). The Makefile passes the
# design name as the sole argument:
#
#     quartus_sh -t <abs path>/blinky.tcl <Blinky|BlinkyWithReset>
#
# with the current working directory set to _build/<NAME>/02-quartus/ (Quartus
# CLI tools are cwd-oriented). It (re)creates the `blinky` project there, writing
# device, source, timing, and pin assignments into blinky.qsf. The discrete
# compile stages (quartus_map/fit/asm/sta) are then driven from the Makefile,
# mirroring the reference repo's yosys/nextpnr/icepack/iceprog split.
#
# Device/clk/led/SDC are shared by both designs; only BlinkyWithReset adds the
# `rst` pin (KEY0). This is the single-file analogue of the reference repo's two
# per-design pcf files, kept DRY so the shared assignments live in one place.
#
# Paths are relative to the project dir (_build/<NAME>/02-quartus/): the Clash
# output is staged one level up in ../01-hdl/ by the Makefile before this runs.

package require ::quartus::project

# Which design are we building? Quartus exposes args after the script in
# $quartus(args). Default to plain Blinky (no reset pin) if none is given.
set design "Blinky"
if {[info exists quartus(args)] && [llength $quartus(args)] >= 1} {
    set design [lindex $quartus(args) 0]
}

# -overwrite: re-run from a clean slate each build; the Makefile owns staleness.
project_new blinky -overwrite

# --- Machine -----------------------------------------------------------------
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL

# --- Device ------------------------------------------------------------------
# Terasic Cyclone V GX Starter Kit (C5G). The chip is marked 5CGXFC5C6F27C7N,
# but Quartus's DEVICE name drops the trailing "N" (the lead-free package
# suffix): the valid device string is 5CGXFC5C6F27C7. This matches Terasic's own
# C5G_Default.qsf; keeping the "N" makes quartus_map fail with "Part name ...
# is illegal".
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CGXFC5C6F27C7

# --- Top level + sources -----------------------------------------------------
# Both modules name their entity `topEntity`; keep Quartus's top in sync so the
# pin assignments below bind to its ports.
set_global_assignment -name TOP_LEVEL_ENTITY topEntity
set_global_assignment -name VERILOG_FILE ../01-hdl/topEntity.v

# --- Timing ------------------------------------------------------------------
# Single source of truth: Clash emits topEntity.sdc from the Dom50 clock domain
# (create_clock, 20 ns / 50 MHz). No hand-written SDC, so the constraint always
# tracks the Haskell clock period.
set_global_assignment -name SDC_FILE ../01-hdl/topEntity.sdc

# --- Pins (shared) -----------------------------------------------------------
# Bind the Clash port names (clk, led) to C5G pin LOCATIONS and I/O STANDARDS.
# The Terasic board labels (CLOCK_50_B5B, LEDR[0]) are irrelevant to Clash; only
# the pin/location/standard matter. Values from Terasic's C5G_Default.qsf:
#
#   clk -> CLOCK_50_B5B -> PIN_R20, 3.3-V LVTTL   (50 MHz oscillator)
#   led -> LEDR[0]      -> PIN_F7,  2.5 V          (red user LED 0)
set_location_assignment PIN_R20 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

set_location_assignment PIN_F7 -to led
set_instance_assignment -name IO_STANDARD "2.5 V" -to led

# --- Pins (BlinkyWithReset only) ---------------------------------------------
# Only the reset variant has an `rst` port, so its pin is added conditionally.
# Assigning to a port the design lacks would draw a Quartus warning; keeping it
# behind the design check mirrors the reference's per-design pin files.
#
#   rst -> KEY[0] -> PIN_P11, 1.2 V (active-low push button; synchronized in HDL)
if {$design eq "BlinkyWithReset"} {
    set_location_assignment PIN_P11 -to rst
    set_instance_assignment -name IO_STANDARD "1.2 V" -to rst
}

# Unused/dual-purpose pins keep Quartus's safe default ("as input tri-stated
# with weak pull-up"); not overridden for this smoke test.

project_close
