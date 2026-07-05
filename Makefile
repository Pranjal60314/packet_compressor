MAKEFLAGS += --no-print-directory

VENV_DIR    := /home/pythonofapollo/WorkSpace/.venv
VENV_PYTHON := $(VENV_DIR)/bin/python3

PYTHON_FILE := /home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/pkt_test.py
LOG_FILE    := /home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/logs/python_sim_log.txt

.PHONY: all run_python

all: run_python

run_python:
	@mkdir -p $(dir $(LOG_FILE))
	$(VENV_PYTHON) $(PYTHON_FILE) 2>&1 | tee -a $(LOG_FILE)

clean:
	rm -f $(LOG_FILE)