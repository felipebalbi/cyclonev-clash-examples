##----------------------------------------------------------------------------##
#   Project Settings                                                           #
##----------------------------------------------------------------------------##
#
# Two-stage build, mirroring the upstream clash-starters `orangecrab` project
# but retargeted from the ECP5 to the Quartus / Cyclone V (C5G) toolchain:
#
#   Stage 1  Clash + GHC compile src/ and emit Verilog        (stack)
#   Stage 2  quartus_sh -t blinky.tcl  (project: device+pins+SDC)
#            quartus_map -> quartus_fit -> quartus_asm -> quartus_sta  (this Makefile)
#            quartus_pgm                                       (JTAG / USB-Blaster)
#
# NAME is the Haskell module holding the top entity; TOP is the entity itself
# (`topEntity`, carrying a makeTopEntity Synthesize annotation). Clash writes its
# HDL to verilog/$(NAME).$(TOP)/. QPROJ is the Quartus project/revision name.
#
# Two designs share this Makefile; select with NAME (default Blinky):
#
#     make                          # plain Blinky (LEDR[0] free-runs)
#     make NAME=BlinkyWithReset     # same blink, held in reset by KEY0
#
# NAME is forwarded to blinky.tcl so it knows whether to add the `rst` pin.

NAME  = Blinky
TOP   = topEntity
QPROJ = blinky

# Build tree, keyed on the design (NAME). Both tops are named `topEntity`, so a
# shared _build would let one design's staged HDL/bitstream masquerade as the
# other's after a NAME switch. Per-design subdirs keep them independent (and let
# both bitstreams coexist). The Clash HDL is staged into 01-hdl/; the Quartus
# project and all its intermediates (db/, reports, .sof) live in 02-quartus/.
BUILDDIR = _build/$(NAME)
HDLDIR   = $(BUILDDIR)/01-hdl
QDIR     = $(BUILDDIR)/02-quartus

# Where Clash drops its output.
CLASHOUT = verilog/$(NAME).$(TOP)

# Quartus stage markers (each discrete CLI tool writes one of these into $(QDIR),
# the way yosys/nextpnr/icepack each produce one artefact in the reference repo).
QSF = $(QDIR)/$(QPROJ).qsf
MAP = $(QDIR)/$(QPROJ).map.rpt
FIT = $(QDIR)/$(QPROJ).fit.rpt
SOF = $(QDIR)/$(QPROJ).sof
STA = $(QDIR)/$(QPROJ).sta.rpt

# Quartus CLI tools are cwd-oriented, so recipes `cd $(QDIR)` first. The project
# script therefore needs an absolute path (it's resolved from the Makefile dir).
TCL = $(abspath $(QPROJ).tcl)

# Tool paths live in build.cfg; copy it to build.cfg.local to override locally.
-include build.cfg
-include build.cfg.local

##----------------------------------------------------------------------------##
#   Build Rules                                                                #
##----------------------------------------------------------------------------##

default: bitstream

# Phony stage aliases, in pipeline order.
project:   $(QSF)
synth:     $(MAP)
fit:       $(FIT)
bitstream: $(SOF)
timing:    $(STA)

# Program the C5G over its built-in USB-Blaster. `.sof` is volatile SRAM config
# (lost on power cycle); flashing the `.pof` is intentionally out of scope.
# `-o "p;<file>"` programs the first device in the JTAG chain; run `jtagconfig`
# to confirm the cable, and add `-c <cable>` / `@<n>` if you have more than one.
program: $(SOF)
	cd $(QDIR) && $(QUARTUS_PGM) -m jtag -o "p;$(QPROJ).sof"

# 6. Timing analysis (off the default path: the .sof already exists; this just
#    reports slack against the Clash-generated 50 MHz constraint).
$(STA): $(SOF)
	cd $(QDIR) && $(QUARTUS_STA) $(QPROJ)

# 5. Assembler: emit the bitstream (.sof) from the fitted design.
$(SOF): $(FIT)
	cd $(QDIR) && $(QUARTUS_ASM) $(QPROJ)

# 4. Fitter: place & route.
$(FIT): $(MAP)
	cd $(QDIR) && $(QUARTUS_FIT) $(QPROJ)

# 3. Analysis & synthesis (Verilog -> internal netlist).
$(MAP): $(QSF)
	cd $(QDIR) && $(QUARTUS_MAP) $(QPROJ)

# 2. Generate the Quartus project (device, pins, sources, SDC) from the TCL.
#    NAME is forwarded so the script adds the `rst` pin only for BlinkyWithReset.
#    Wipe any prior project first: `project_new -overwrite` still *reads* a stale
#    .qsf before replacing it, so a leftover (e.g. a bad DEVICE) would abort the
#    run. Regenerating the project means downstream stages recompile anyway.
$(QSF): $(HDLDIR)/$(TOP).v $(QPROJ).tcl
	rm -rf $(QDIR)
	mkdir -p $(QDIR)
	cd $(QDIR) && $(QUARTUS_SH) -t $(TCL) $(NAME)

# 1b. Stage the Clash-generated HDL (and its SDC) into the build tree.
$(HDLDIR)/$(TOP).v: $(CLASHOUT)/$(TOP).v
	mkdir -p $(BUILDDIR)
	rm -rf $(HDLDIR)
	cp -a $(CLASHOUT) $(HDLDIR)

# 1a. Generate Verilog from Clash. Upstream orangecrab leaves this to a manual
#     `stack run clash -- Blinky --verilog`; we wire it into make so the whole
#     pipeline runs from a single `make`.
$(CLASHOUT)/$(TOP).v: $(shell find src -name '*.hs')
	$(CLASH) $(NAME) --verilog

##----------------------------------------------------------------------------##
#   Tests                                                                      #
##----------------------------------------------------------------------------##

# Run the tasty unit-test suite (tests/unittests.hs): pure-Haskell simulation
# of the counter, independent of the Quartus toolchain.
test:
	$(TEST)

##----------------------------------------------------------------------------##
#   Cleanup                                                                    #
##----------------------------------------------------------------------------##

clean:
	rm -rf _build verilog

##----------------------------------------------------------------------------##
#   Special Targets                                                            #
##----------------------------------------------------------------------------##

.PHONY: default project synth fit bitstream timing program test clean
.SECONDARY:
