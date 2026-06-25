# Quartus project-generation script for the C5G pwm-wave example.
#
# Run by the Makefile as:  quartus_sh -t <abs path>/pwm-wave.tcl <NAME>
# with the cwd set to _build/<NAME>/02-quartus/ (Quartus CLI tools are
# cwd-oriented). It (re)creates the `pwm-wave` project there, writing device,
# source, timing, and pin assignments into pwm-wave.qsf. The discrete compile
# stages (quartus_map/fit/asm/sta) are then driven from the Makefile, mirroring
# the reference repo's yosys/nextpnr/icepack/iceprog split.
#
# Paths are relative to the project dir (_build/<NAME>/02-quartus/): the Clash
# output is staged one level up in ../01-hdl/ by the Makefile before this runs.
#
# Single top (PwmWave); NAME is forwarded only for parity with the sibling
# examples' build machinery, and is unused here (one design, fixed pins).

package require ::quartus::project

# -overwrite: re-run from a clean slate each build; the Makefile owns staleness.
# The project name must match the Makefile's QPROJ (pwm-wave) so the discrete
# stages (quartus_map pwm-wave, ...) find the revision they expect.
project_new pwm-wave -overwrite

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
# create_clock at the domain's 20 ns / 50 MHz period). No hand-written SDC, so
# the constraint always tracks the Haskell clock period.
set_global_assignment -name SDC_FILE ../01-hdl/topEntity.sdc

# --- Pins --------------------------------------------------------------------
# Bind the Clash port names to C5G pin LOCATIONS and I/O STANDARDS. The Terasic
# board labels (CLOCK_50_B5B, LEDR[9:0], LEDG[7:0]) are irrelevant to Clash;
# only the pin/location/standard matter. The `Vec n Bit` output ports render as
# packed [n-1:0] buses, so ledr[$i] / ledg[$i] bind index by index, matching the
# generated Verilog. Values from Terasic's C5G_Default.qsf:
#
#   clk       -> CLOCK_50_B5B -> PIN_R20, 3.3-V LVTTL   (50 MHz oscillator)
#   ledr[9:0] -> LEDR[9:0],     all 2.5 V               (red user LEDs)
#   ledg[7:0] -> LEDG[7:0],     all 2.5 V               (green user LEDs)
set_location_assignment PIN_R20 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# Red bank LEDR[9:0] -> ledr[9:0].
set ledr_pins {PIN_F7 PIN_F6 PIN_G6 PIN_G7 PIN_J8 PIN_J7 PIN_K10 PIN_K8 PIN_H7 PIN_J10}
for {set i 0} {$i < 10} {incr i} {
    set_location_assignment [lindex $ledr_pins $i] -to ledr[$i]
    set_instance_assignment -name IO_STANDARD "2.5 V" -to ledr[$i]
}

# Green bank LEDG[7:0] -> ledg[7:0].
set ledg_pins {PIN_L7 PIN_K6 PIN_D8 PIN_E9 PIN_A5 PIN_B6 PIN_H8 PIN_H9}
for {set i 0} {$i < 8} {incr i} {
    set_location_assignment [lindex $ledg_pins $i] -to ledg[$i]
    set_instance_assignment -name IO_STANDARD "2.5 V" -to ledg[$i]
}

# SW[0] -> PIN_AC9 (1.2 V) is reserved for the v2 gamma/triangle kernel select.

# Unused/dual-purpose pins keep Quartus's safe default ("as input tri-stated
# with weak pull-up"); not overridden for this smoke test.

project_close
