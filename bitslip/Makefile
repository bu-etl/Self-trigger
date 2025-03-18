TOPLEVEL_LANG ?= vhdl
MODULE = bitslip_tb
TOPLEVEL = bitslip

# Path to source files
VHDL_SOURCES = $(shell pwd)/vhdl/bitslip.vhd

# Specify the simulator if needed (GHDL in this case)
SIM ?= ghdl

# GHDL arguments
GHDL_ARGS += --std=08

# Add VCD dumping during simulation
SIM_ARGS += --vcd=waves.vcd

# Add 'tests' directory to PYTHONPATH
export PYTHONPATH := $(PYTHONPATH):$(shell pwd)/tests

# Resolve undefined ('U') bits in simulation to '0'
export COCOTB_RESOLVE_X = ZEROS

# Include Cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim

view:
	gtkwave waves.vcd &

