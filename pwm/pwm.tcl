# Quartus project-generation script for the C5G pwm example.
#
# Run by the Makefile as:  quartus_sh -t <abs path>/pwm.tcl <NAME>
# with the current working directory set to _build/<NAME>/02-quartus/ (Quartus
# CLI tools are cwd-oriented). It (re)creates the `pwm` project there, writing
# device, source, timing, and pin assignments into pwm.qsf. The discrete compile
# stages (quartus_map/fit/asm/sta) are then driven from the Makefile, mirroring
# the reference repo's yosys/nextpnr/icepack/iceprog split.
#
# Paths are relative to the project dir (_build/<NAME>/02-quartus/): the Clash
# output is staged one level up in ../01-hdl/ by the Makefile before this runs.
#
# SCAFFOLD: the pin assignments below assume a single PWM-driven LED on the same
# clk/led ports as blinky. Adjust them to match your topEntity's actual port
# names once the Clash source exists (see the "more pins" note near the bottom).

package require ::quartus::project

# Which design are we building? Quartus exposes args after the script in
# $quartus(args). Default to Pwm; forwarded by the Makefile's $(NAME). Use this
# if you add a second top (e.g. a pattern-generator variant) that needs extra
# pins, the way blinky's tcl keys the `rst` pin off the design name.
set design "Pwm"
if {[info exists quartus(args)] && [llength $quartus(args)] >= 1} {
    set design [lindex $quartus(args) 0]
}

# -overwrite: re-run from a clean slate each build; the Makefile owns staleness.
project_new pwm -overwrite

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
# Single source of truth: Clash emits topEntity.sdc from the clock domain (a
# create_clock at the domain's period). No hand-written SDC, so the constraint
# always tracks the Haskell clock period.
set_global_assignment -name SDC_FILE ../01-hdl/topEntity.sdc

# --- Pins --------------------------------------------------------------------
# Bind the Clash port names to C5G pin LOCATIONS and I/O STANDARDS. The Terasic
# board labels (CLOCK_50_B5B, LEDR[0]) are irrelevant to Clash; only the
# pin/location/standard matter. Values from Terasic's C5G_Default.qsf:
#
#   clk -> CLOCK_50_B5B -> PIN_R20, 3.3-V LVTTL   (50 MHz oscillator)
#   led -> LEDR[0]      -> PIN_F7,  2.5 V          (red user LED 0)
set_location_assignment PIN_R20 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

set_location_assignment PIN_F7 -to led
set_instance_assignment -name IO_STANDARD "2.5 V" -to led

# --- More pins (uncomment / extend as the design grows) ----------------------
# A vector output port `led :: Signal dom (BitVector 10)` binds index by index.
# This is the LEDR[9:0] bank from C5G_Default.qsf, handy for a PWM pattern
# generator across all red LEDs:
#
#   set_location_assignment PIN_F7  -to led[0]
#   set_location_assignment PIN_F6  -to led[1]
#   set_location_assignment PIN_G6  -to led[2]
#   set_location_assignment PIN_G7  -to led[3]
#   set_location_assignment PIN_J8  -to led[4]
#   set_location_assignment PIN_J7  -to led[5]
#   set_location_assignment PIN_K10 -to led[6]
#   set_location_assignment PIN_K8  -to led[7]
#   set_location_assignment PIN_H7  -to led[8]
#   set_location_assignment PIN_J10 -to led[9]
#   foreach i {0 1 2 3 4 5 6 7 8 9} {
#       set_instance_assignment -name IO_STANDARD "2.5 V" -to led[$i]
#   }
#
# Slide switches SW[9:0] make a convenient duty/speed input (1.2 V); KEY[3:0]
# are the push buttons (1.2 V, active-low). Add them the same way when needed.

# Unused/dual-purpose pins keep Quartus's safe default ("as input tri-stated
# with weak pull-up"); not overridden for this smoke test.

project_close
