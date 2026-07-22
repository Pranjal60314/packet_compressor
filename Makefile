MAKEFLAGS += --no-print-directory                     
                                                                                
VENV_DIR    := /home/pythonofapollo/WorkSpace/.venv
VENV_PYTHON := $(VENV_DIR)/bin/python3
RUNNER_FILE := /home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/makefile_configs/run_pipeline.py

.PHONY: all test

all: test

test:
	@$(VENV_PYTHON) $(RUNNER_FILE)