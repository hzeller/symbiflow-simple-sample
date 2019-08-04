# Basys3 board using SymbiFlow, making it simple to understand
# what to run with a straight-forward Makefile.
#
# (c) Henner Zeller <hzeller@google.com>
# http://www.apache.org/licenses/LICENSE-2.0
#
# Set the environment variable SYMBIFLOW_ARCH_DEFS
# to wherever the toplevel of your symbiflow-arch-defs
# is checked out.
#
# Call
#  make prog
# To synthesize for Basys3 board.
#
# Current binaries needed in the process point to the versions
# checked out via conda in symbiflow, but feel free to
# set the following environment variables to run your own
#  - YOSYS_BIN
#  - VPR_BIN
#  - GENFASM_BIN
#  - OPENOCD_BIN
# to point to local versions of these binaries.
##

SHELL := /bin/bash

PROJECT=counter

# Point this where symbiflow-arch-defs is checked out
SYMBIFLOW_ARCH_DEFS?=~/src/symbiflow-arch-defs

# Build environment coming with symbiflow: some binaries at the right version, as
# symbiflow might be somtimes either pin a version or be ahead.
CONDA_DIR=$(SYMBIFLOW_ARCH_DEFS)/build/env/conda

#-- Yosis
YOSYS_BIN?=$(CONDA_DIR)/bin/yosys

#-- io place
IOPLACE=PYTHONPATH=$(SYMBIFLOW_ARCH_DEFS)/utils python3 $(SYMBIFLOW_ARCH_DEFS)/xc7/utils/prjxray_create_ioplace.py
PCF=basys3.pcf
MAP=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/xc7a50t-basys3-roi-virt/synth_tiles_pinmap.csv

#-- VPR
# TODO: fix vpr to set logfile from flag.
export VPR_LOG_FILE=
VPR_BIN?=$(CONDA_DIR)/bin/vpr

DEVICE=xc7a50t-basys3-test
ARCH_TIMING_XML=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/xc7a50t-basys3-roi-virt/arch.timing.xml
RR_GRAPH=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/rr_graph_xc7a50t-basys3_test.rr_graph.real.xml
VPR_PARAMS=--min_route_chan_width_hint 100 \
           --max_criticality 0.0 --max_router_iterations 500 \
           --routing_failure_predictor off --router_high_fanout_threshold -1 \
           --constant_net_method route --route_chan_width 500 \
           --clock_modeling route --place_algorithm bounding_box \
           --enable_timing_computations off --allow_unrelated_clustering on \
           --clustering_pin_feasibility_filter off --disable_check_route on \
           --strict_checks off --allow_dangling_combinational_nodes on \
           --disable_errors check_unbuffered_edges:check_route


# FASM
GENFASM_BIN?=$(CONDA_DIR)/bin/genfasm

# Convert FASM to frames
FASM2FRAMES=PYTHONPATH=$(CONDA_DIR)/lib/python3.7/site-packages:$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray:$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/third_party/fasm python3 $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/utils/fasm2frames.py

# XC patch
XC7PATCH=$(SYMBIFLOW_ARCH_DEFS)/build/third_party/prjxray/tools/xc7patch

# Flashing. Just use good 'ol openocd. Everyone should've installed that on their machine.
OPENOCD_BIN?=$(CONDA_DIR)/bin/openocd
DIGILENT_CONFIG=openocd-digilent-basys3.cfg


all: top.bit

%.eblif : %.v synth.tcl
	symbiflow_arch_defs_SOURCE_DIR=$(SYMBIFLOW_ARCH_DEFS) \
        OUT_EBLIF=$@ \
        $(YOSYS_BIN) -q -p "tcl synth.tcl" -l $@.log $<

%_io.place : %.eblif
	$(IOPLACE) --pcf $(PCF) --map $(MAP) --blif $^ --out $@

%.net: %.eblif
	$(VPR_BIN) $(ARCH_TIMING_XML) $< --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --pack > $*-pack.log

%.place: %.eblif %_io.place %.net
	$(VPR_BIN) $(ARCH_TIMING_XML) $*.eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --fix_pins $*_io.place --place > $*-place.log

%.route: %.eblif %.place
	$(VPR_BIN) $(ARCH_TIMING_XML) $*.eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --route > $*-route.log

top.fasm: $(PROJECT).eblif $(PROJECT).place $(PROJECT).route $(PROJECT).net
	$(GENFASM_BIN) $(ARCH_TIMING_XML) $(PROJECT).eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) > fasm.log

top.frames: top.fasm
	$(FASM2FRAMES) --db-root $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7 --sparse --roi $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/basys3/swbut/design.json $< $@

%.bit: %.frames
	$(XC7PATCH) --frm_file $^ --output_file $@ --bitstream_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/basys3/swbut/design.bit --part_name xc7a35tcpg236-1 --part_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/xc7a35tcpg236-1.yaml

prog: top.bit
	$(OPENOCD_BIN) -f $(DIGILENT_CONFIG) -c "init ; pld load 0 $^ ; exit"

clean:
	rm -f $(PROJECT).eblif $(PROJECT)_synth.v
	rm -f $(PROJECT)_io.place $(PROJECT).{net,place,route}
	rm -f top.frames top.fasm top.bit top_synth.v
	rm -f $(PROJECT)-{pack,place,route}.log $(PROJECT).eblif.log fasm.log
	rm -f *.rpt
