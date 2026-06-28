# Quartus project-generation script for the C5G sevenseg example.
#
# Run by the Makefile as:  quartus_sh -t <abs path>/sevenseg.tcl <NAME>
# with the cwd set to _build/<NAME>/02-quartus/ (Quartus CLI tools are
# cwd-oriented). It (re)creates the `sevenseg` project there, writing device,
# source, timing, and pin assignments into sevenseg.qsf. The discrete compile
# stages (quartus_map/fit/asm/sta) are then driven from the Makefile, mirroring
# the reference repo's yosys/nextpnr/icepack/iceprog split.
#
# Paths are relative to the project dir (_build/<NAME>/02-quartus/): the Clash
# output is staged one level up in ../01-hdl/ by the Makefile before this runs.
#
# Single top (SevenSeg); NAME is forwarded only for parity with the sibling
# examples' build machinery, and is unused here (one design, fixed pins).

package require ::quartus::project

# -overwrite: re-run from a clean slate each build; the Makefile owns staleness.
# The project name must match the Makefile's QPROJ (sevenseg) so the discrete
# stages (quartus_map sevenseg, ...) find the revision they expect.
project_new sevenseg -overwrite

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
# board labels (CLOCK_50_B5B, HEX0..HEX3) are irrelevant to Clash; only the
# pin/location/standard matter. The `BitVector 7` output ports render as packed
# [6:0] buses, so hex<d>[$i] binds index by index. Pin-list index i = segment i
# (a..g), matching C5G HEX<d>[i], so hex<d>[i] drives HEX<d>[i]. Values from
# Terasic's C5G_Default.qsf.
#
# IMPORTANT: the four digits are NOT on one I/O standard — HEX0/HEX1 are 1.2 V,
# HEX2/HEX3 are 3.3-V LVTTL — so each digit carries its own standard (unlike
# pwm-wave's single-standard ledr/ledg loops).
set_location_assignment PIN_R20 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk

# Bind one 7-segment digit: port `hex<d>`, its 7 pins (seg a..g), I/O standard.
proc bind_hex {port pins iostd} {
    for {set i 0} {$i < 7} {incr i} {
        set_location_assignment [lindex $pins $i] -to ${port}[$i]
        set_instance_assignment -name IO_STANDARD $iostd -to ${port}[$i]
    }
}

#          port   {seg a    b        c        d        e        f        g      }  I/O standard
bind_hex   hex0  {PIN_V19  PIN_V18  PIN_V17  PIN_W18  PIN_Y20  PIN_Y19  PIN_Y18}  "1.2 V"
bind_hex   hex1  {PIN_AA18 PIN_AD26 PIN_AB19 PIN_AE26 PIN_AE25 PIN_AC19 PIN_AF24} "1.2 V"
bind_hex   hex2  {PIN_AD7  PIN_AD6  PIN_U20  PIN_V22  PIN_V20  PIN_W21  PIN_W20}  "3.3-V LVTTL"
bind_hex   hex3  {PIN_Y24  PIN_Y23  PIN_AA23 PIN_AA22 PIN_AC24 PIN_AC23 PIN_AC22} "3.3-V LVTTL"

# Unused/dual-purpose pins keep Quartus's safe default ("as input tri-stated
# with weak pull-up"); not overridden for this smoke test.

project_close
