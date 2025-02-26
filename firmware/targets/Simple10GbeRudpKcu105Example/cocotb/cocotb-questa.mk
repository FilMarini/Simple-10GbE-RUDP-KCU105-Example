# Define TOP_DIR
export PWD = $(shell pwd)
export TOP_DIR=$(abspath $(PWD)/../../../../..)

# Some cocotb env variables
export PYTHONPATH=$(TOP_DIR)/targets/blueSurf/cocotb
export GPI_EXTRA=$(shell cocotb-config --lib-name-path vpi questa):cocotbvpi_entry_point

# Define test variables
export LOCAL_PSN=18697
export REM_QPN=17
export REM_PSN=18695
export REM_RKEY=759
export REM_ADDR=94044413001728
export CHECK_ACK=True
export INTERFACE=vboxnet0

# Make variables
MODULE := TestBlueSurf
LIBPYTHON_LOC := $(shell cocotb-config --libpython)
COCOTB_RESOLVE_X := ZEROS

run: simv
	MODULE=$(MODULE) LIBPYTHON_LOC=$(LIBPYTHON_LOC) COCOTB_RESOLVE_X=$(COCOTB_RESOLVE_X) ./simv

simv: sim_msim.sh
	./sim_msim.sh

.PHONY: run

