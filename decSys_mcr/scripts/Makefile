# Tool definitions
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Directory paths
OUT_DIR = ../output

# ----------------------------------------------------
# DYNAMIC TESTBENCH SELECTION
# Default to tb_sdlc_loopback if no TB is specified
TB ?= tb_sdlc_loopback
# ----------------------------------------------------

# File references
FILELIST = design_sources
TB_FILE = ../tb/$(TB).sv
TOP_WAVEFORM = $(TB).vcd
SIM_EXEC = sim.vvp

# Icarus flags
IVERILOG_FLAGS = -g2012 -Wall

.PHONY: all compile simulate wave clean setup

all: setup compile simulate wave

# Robust directory creation (the '-' ignores errors if the folder already exists)
setup:
	-@mkdir "$(OUT_DIR)" 2>nul || echo ""

# FIX: Moved the '-o' flag to the front before the filelist and testbench
compile: setup
	@echo "##### COMPILING $(TB) #####"
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(OUT_DIR)/$(SIM_EXEC) -c $(FILELIST) $(TB_FILE)

simulate: compile
	@echo "##### RUNNING SIMULATION #####"
	cd $(OUT_DIR) && $(VVP) $(SIM_EXEC) +vcdfile=$(TOP_WAVEFORM)

wave:
	@echo "##### OPENING GTKWAVE #####"
	cmd /c start /b $(GTKWAVE) $(OUT_DIR)/$(TOP_WAVEFORM)

clean:
	@if exist "$(OUT_DIR)" rmdir /s /q "$(OUT_DIR)"