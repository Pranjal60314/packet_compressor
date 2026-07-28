MAKEFLAGS += --no-print-directory

VENV_DIR    ?= .venv
VENV_PYTHON := $(shell if [ -f "$(VENV_DIR)/bin/python3" ]; then echo "$(VENV_DIR)/bin/python3"; else which python3; fi)

RUNNER_FILE := build/makefile_configs/run_pipeline.py

.PHONY: all test

all: test

test:
	@$(VENV_PYTHON) $(RUNNER_FILE)