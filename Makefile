SHELL := /bin/bash

PROJECT=counter

# Point this where symbiflow-arch-defs is checked out
SYMBIFLOW_ARCH_DEFS?=/home/hzeller/src/symbiflow-arch-defs

#-- Yosis
YOSYS=/usr/local/bin/yosys

#-- io place
IOPLACE=PYTHONPATH=$(SYMBIFLOW_ARCH_DEFS)/utils python3 $(SYMBIFLOW_ARCH_DEFS)/xc7/utils/prjxray_create_ioplace.py
PCF=basys3.pcf
MAP=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/xc7a50t-basys3-roi-virt/synth_tiles_pinmap.csv


#-- VPR
# TODO: fix vpr to set logfile from flag.
export VPR_LOG_FILE=
VPR=/usr/local/bin/vpr
#VPR=$(SYMBIFLOW_ARCH_DEFS)/build/env/conda/bin/vpr

DEVICE=xc7a50t-basys3-test
ARCH_PACK_XML=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/xc7a50t-basys3-roi-virt/arch.unique_pack.xml
RR_GRAPH=$(SYMBIFLOW_ARCH_DEFS)/build/xc7/archs/artix7/devices/rr_graph_xc7a50t-basys3_test.rr_graph.real.xml
VPR_PARAMS=--min_route_chan_width_hint 100 \
           --max_criticality 0.0 --max_router_iterations 500 \
           --routing_failure_predictor off --router_high_fanout_threshold -1 \
           --constant_net_method route --route_chan_width 500 \
           --clock_modeling route --place_algorithm bounding_box \
           --enable_timing_computations off --allow_unrelated_clustering on \
           --round_robin_prepacking on


# FASM
GENFASM=/usr/local/bin/genfasm
#GENFASM=$(SYMBIFLOW_ARCH_DEFS)/build/env/conda/bin/genfasm


# Convert FASM to frames
FASM2FRAMES=PYTHONPATH=$(SYMBIFLOW_ARCH_DEFS)/build/env/conda/lib/python3.7/site-packages:$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray:$(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/third_party/fasm python3 $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray/utils/fasm2frames.py


# XC patch
XC7PATCH=$(SYMBIFLOW_ARCH_DEFS)/build/third_party/prjxray/tools/xc7patch


# Flashing. Just use good 'ol openocd
OPENOCD=openocd
DIGILENT_CONFIG=openocd-digilent-basys3.cfg


all: top.bit

%.eblif : %.v
	symbiflow_arch_defs_SOURCE_DIR=$(SYMBIFLOW_ARCH_DEFS) \
        OUT_EBLIF=$@ \
        $(YOSYS) -q -p "tcl synth.tcl" -l $@.log $^

%_io.place : %.eblif
	$(IOPLACE) --pcf $(PCF) --map $(MAP) --blif $^ --out $@

# pack
%.net: %.eblif
	$(VPR) $(ARCH_PACK_XML) counter.eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --pack > $*-pack.log

# place
%.place: %.eblif %_io.place %.net
	$(VPR) $(ARCH_PACK_XML) $*.eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --fix_pins counter_io.place --place > $*-place.log

%.route: %.eblif %.place
	$(VPR) $(ARCH_PACK_XML) $*.eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) --route > $*-route.log

top.fasm: $(PROJECT).eblif $(PROJECT).place $(PROJECT).route $(PROJECT).net
	$(GENFASM) $(ARCH_PACK_XML) $(PROJECT).eblif --device $(DEVICE) --read_rr_graph $(RR_GRAPH) $(VPR_PARAMS) > fasm.log

top.frames: top.fasm
	$(FASM2FRAMES) --db-root $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7 --sparse --roi $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/basys3/swbut/design.json $< $@

%.bit: %.frames
	$(XC7PATCH) --frm_file $^ --output_file $@ --bitstream_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/harness/basys3/swbut/design.bit --part_name xc7a35tcpg236-1 --part_file $(SYMBIFLOW_ARCH_DEFS)/third_party/prjxray-db/artix7/xc7a35tcpg236-1.yaml

prog: top.bit
	$(OPENOCD) -f $(DIGILENT_CONFIG) -c "init ; pld load 0 $^ ; exit"

clean:
	rm -f $(PROJECT).eblif $(PROJECT)_synth.v
	rm -f $(PROJECT)_io.place $(PROJECT).{net,place,route}
	rm -f top.frames top.fasm top.bit top_synth.v
	rm -f $(PROJECT)-{pack,place,route}.log $(PROJECT).eblif.log fasm.log
	rm -f *.rpt
