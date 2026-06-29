# Quartus project-generation script for the C5G pushbutton example.
#
# Run by the Makefile as:  quartus_sh -t <abs path>/pushbutton.tcl <NAME>
# with the cwd set to _build/<NAME>/02-quartus/ (Quartus CLI tools are
# cwd-oriented). It (re)creates the `pushbutton` project there, writing device,
# source, timing, and pin assignments into pushbutton.qsf. The discrete compile
# stages (quartus_map/fit/asm/sta) are then driven from the Makefile, mirroring
# the reference repo's yosys/nextpnr/icepack/iceprog split.
#
# Paths are relative to the project dir (_build/<NAME>/02-quartus/): the Clash
# output is staged one level up in ../01-hdl/ by the Makefile before this runs.
#
# Single top (PushButton); NAME is forwarded only for parity with the sibling
# examples' build machinery, and is unused here (one design, fixed pins).

package require ::quartus::project

# -overwrite: re-run from a clean slate each build; the Makefile owns staleness.
# The project name must match the Makefile's QPROJ (pushbutton) so the discrete
# stages (quartus_map pushbutton, ...) find the revision they expect.
project_new pushbutton -overwrite

# --- Machine -----------------------------------------------------------------
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL

# --- Device ------------------------------------------------------------------
# Terasic Cyclone V GX Starter Kit (C5G). The chip is marked 5CGXFC5C6F27C7N,
# but Quartus's DEVICE name drops the trailing "N" (the lead-free package
# suffix): the valid device string is 5CGXFC5C6F27C7. Keeping the "N" makes
# quartus_map fail with "Part name ... is illegal".
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CGXFC5C6F27C7

# --- Top level + sources -----------------------------------------------------
# Clash names the entity `topEntity`; keep Quartus's top in sync so the pin
# assignments below bind to its ports.
set_global_assignment -name TOP_LEVEL_ENTITY topEntity
set_global_assignment -name VERILOG_FILE ../01-hdl/topEntity.v

# --- Timing ------------------------------------------------------------------
# Single source of truth: Clash emits topEntity.sdc from the Dom50 clock domain
# (a create_clock at the domain's 20 ns / 50 MHz period). No hand-written SDC, so
# the constraint always tracks the Haskell clock period.
set_global_assignment -name SDC_FILE ../01-hdl/topEntity.sdc

# --- Pins --------------------------------------------------------------------
# Bind the Clash port names (clk, key0, led) to C5G pin LOCATIONS and I/O
# STANDARDS. The Terasic board labels (CLOCK_50_B5B, KEY[0], LEDR[0]) are
# irrelevant to Clash; only the pin/location/standard matter. Values from
# Terasic's C5G_Default.qsf.
#
# IMPORTANT: the three ports are on THREE different I/O standards (mixed-voltage
# banks): the 50 MHz clock is 3.3-V LVTTL, KEY[0] is 1.2 V, and LEDR[0] is 2.5 V.
# Each port therefore carries its own standard.
#
#   clk  -> CLOCK_50_B5B -> PIN_R20, 3.3-V LVTTL   (50 MHz oscillator)
#   key0 -> KEY[0]       -> PIN_P11, 1.2 V          (active-low push button, RC-debounced)
#   led  -> LEDR[0]      -> PIN_F7,  2.5 V          (red user LED 0)
set_location_assignment PIN_R20 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

set_location_assignment PIN_P11 -to key0
set_instance_assignment -name IO_STANDARD "1.2 V" -to key0

set_location_assignment PIN_F7 -to led
set_instance_assignment -name IO_STANDARD "2.5 V" -to led

# Unused/dual-purpose pins keep Quartus's safe default ("as input tri-stated
# with weak pull-up"); not overridden for this smoke test.

project_close
