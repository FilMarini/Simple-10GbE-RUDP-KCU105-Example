# Define target output
target: prom

# Define Firmware Version: v2.15.0.0
export PRJ_VERSION = 0x02150000

# Define target part
export PRJ_PART = XCKU040-FFVA1156-2-E

# Define the TOP_DIR path
export TOP_DIR = $(abspath $(PWD)/../..)

# Using XVC Debug bridge
export USE_XVC_DEBUG = 1

# Setup for releases.yaml
export RELEASE = simple_10gbe_rudp_kcu105_example

# RoCE co-simulation
export VIVADO_PROJECT_SIM = Simple10GbeRudpKcu105ExampleRoceTb
export MSIM_LIB_PATH = /home/fmarini/.vivado_libs/questa234/Vivado_2023.1
export MSIM_RUN_FLAGS = -foreign \"cocotb_init \$$(cocotb-config --lib-name-path fli questa)\"
export MSIM_DUMP_VCD = true
export VIVADO_PROJECT_SIM_TIME = all

# Use top level makefile
include ../../submodules/ruckus/system_vivado.mk
