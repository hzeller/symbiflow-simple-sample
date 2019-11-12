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

SHELL:=/bin/bash

# Point this where symbiflow-arch-defs is checked out
SYMBIFLOW_ARCH_DEFS?=~/src/symbiflow-arch-defs

CONDA_DIR=$(SYMBIFLOW_ARCH_DEFS)/build/env/conda

BASE_DIR=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices

# Verilog to netlist
YOSYS_BIN?=$(CONDA_DIR)/bin/yosys

# Place and route
VPR_BIN?=$(CONDA_DIR)/bin/vpr

# Place and route parameters, some are just added to speedup the computation
VPR_PARAMS=--min_route_chan_width_hint 100 \
	--max_criticality 0.0 --max_router_iterations 500 \
	--routing_failure_predictor off --router_high_fanout_threshold -1 \
	--constant_net_method route --route_chan_width 500 \
	--clock_modeling route --place_algorithm bounding_box \
	--enable_timing_computations off --allow_unrelated_clustering on \
	--clustering_pin_feasibility_filter off --disable_check_route on \
	--strict_checks off --allow_dangling_combinational_nodes on \
	--disable_errors check_unbuffered_edges:check_route

# Abstract bit-stream representation
GENFASM_BIN?=$(CONDA_DIR)/bin/genfasm
GENFASM_PARAMS=--route_chan_width 500

# Debugger/flasher
OPENOCD_BIN?=openocd

# I/O place
IOPLACE=PYTHONPATH=$(SYMBIFLOW_ARCH_DEFS)/utils \
	python3 $(SYMBIFLOW_ARCH_DEFS)/xc7/utils/prjxray_create_ioplace.py

# Convert FASM to frames
FASM2FRAMES=PYTHONPATH=$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray:$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/third_party/fasm python3 $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/utils/fasm2frames.py

# Convert frames to bitstream
XC7PATCH=$(SYMBIFLOW_ARCH_DEFS)/build/third_party/prjxray/tools/xc7patch

# Symbiflow make targets and files
TARGET?=xc7a50t-basys3

DEVICE=$(TARGET)-test

ARCH_PINMAP_TARGET?=file_xc7_archs_artix7_devices_$(TARGET)-roi-virt_synth_tiles_pinmap.csv
ARCH_PINMAP_MAKE_DIR=$(BASE_DIR)
ARCH_PINMAP=$(BASE_DIR)/$(TARGET)-roi-virt/synth_tiles_pinmap.csv

ARCH_TIMING_TARGET?=file_xc7_archs_artix7_devices_$(TARGET)-roi-virt_arch.timing.xml
ARCH_TIMING_MAKE_DIR=$(BASE_DIR)/$(TARGET)-roi-virt
ARCH_TIMING=$(BASE_DIR)/$(TARGET)-roi-virt/arch.timing.xml

RR_GRAPH_TARGET?=file_xc7_archs_artix7_devices_rr_graph_$(TARGET)_test.lookahead.bin
RR_GRAPH_MAKE_DIR=$(BASE_DIR)
RR_GRAPH?=$(BASE_DIR)/rr_graph_$(TARGET)_test.rr_graph.real.xml

# Maps the FPGA IOs to the top module verilog symbols.
PCF=basys3.pcf

# Flashing. Just use good 'ol openocd. Everyone should've installed that on their machine.
DIGILENT_CONFIG?=openocd-digilent-basys3.cfg

PROJECT?=counter

all: $(PROJECT).bit

# Build the rr graph from symbiflow
$(RR_GRAPH):
	$(MAKE) -C $(RR_GRAPH_MAKE_DIR) $(RR_GRAPH_TARGET)

$(ARCH_PINMAP):
	$(MAKE) -C $(ARCH_PINMAP_MAKE_DIR) $(ARCH_PINMAP_TARGET)

$(ARCH_TIMING): $(ARCH_PINMAP)
	$(MAKE) -C $(ARCH_TIMING_MAKE_DIR) $(ARCH_TIMING_TARGET)

%.eblif : %.v synth.tcl
	symbiflow_arch_defs_SOURCE_DIR=$(SYMBIFLOW_ARCH_DEFS) OUT_EBLIF=$@ \
		$(YOSYS_BIN) -q -p "tcl synth.tcl" -l $@.log $<

%.net: %.eblif $(ARCH_TIMING) $(RR_GRAPH)
	$(VPR_BIN) $(ARCH_TIMING) $< --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --pack > $*-pack.log

%_io.place : %.eblif %.net $(ARCH_PINMAP)
	$(IOPLACE) --pcf $(PCF) --map $(ARCH_PINMAP) --blif $< --net $*.net  --out $@

%.place: %.eblif %_io.place %.net
	$(VPR_BIN) $(ARCH_TIMING) $*.eblif\
		--device $(DEVICE) \
		--read_rr_graph $(RR_GRAPH) \
		--fix_pins $*_io.place --place \
		$(VPR_PARAMS) > $*-place.log

%.route: %.eblif %.place
	$(VPR_BIN) $(ARCH_TIMING) $*.eblif \
		--device $(DEVICE) \
		--read_rr_graph $(RR_GRAPH) \
		$(VPR_PARAMS) --route > $*-route.log

top.fasm: $(PROJECT).eblif $(PROJECT).place $(PROJECT).route $(PROJECT).net
	$(GENFASM_BIN) $(ARCH_TIMING) $(PROJECT).eblif \
		--device $(DEVICE) \
		$(VPR_PARAMS) \
		--read_rr_graph $(RR_GRAPH)> fasm.log

$(PROJECT).frames: top.fasm
	$(FASM2FRAMES) \
		--db-root $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7 \
		--sparse --roi $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/arty-a7/swbut/design.json $< $@

%.bit: %.frames
	$(XC7PATCH) --frm_file $^ \
		--output_file $@ \
		--bitstream_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/arty-a7/swbut/design.bit \
		--part_name xc7a35tcpg236-1 --part_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/xc7a35tcpg236-1.yaml

prog: $(PROJECT).bit
	$(OPENOCD_BIN) -f $(DIGILENT_CONFIG) -c "init ; pld load 0 $^ ; exit"

clean:
	rm -f $(PROJECT).eblif $(PROJECT)_synth.v
	rm -f $(PROJECT)_io.place $(PROJECT).{net,place,route}
	rm -f $(PROJECT).frames top.fasm $(PROJECT).bit
	rm -f $(PROJECT)-{pack,place,route}.log $(PROJECT).eblif.log fasm.log
	rm -f *.rpt
	rm -f *.log
