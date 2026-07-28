
# Running the Project

## Comprehensive Software Benchmark

To perform a comprehensive benchmark of the compression algorithm:

1. Navigate to `build/makefile_configs/pathfiles.py`.
2. Configure the desired datasets and testing parameters.
3. Run:

```bash
python pkt_test.py
```

This script benchmarks the compression pipeline across multiple datasets and records various performance metrics, including:

* Compression Ratio
* Entropy
* Delta Statistics
* Rice Parameter Distribution
* Bits per Sample
* Other dataset-specific metrics

Detailed iteration results are written to:

```text
logs/iteration_profiles.csv
```

while an execution summary is available in

```text
logs/python_sim_log.txt
```

---

# Project Structure

```text
.
├── Makefile
├── README.md
├── build
│   ├── makefile_configs
│   └── telemetry_test
├── logs
├── rtl
├── src
└── tb
```

### Directory Overview

| Directory | Description                                                                |
| --------- | -------------------------------------------------------------------------- |
| `rtl/`    | RTL implementation of the compressor modules.                              |
| `src/`    | Reference C implementation used for validation.                            |
| `tb/`     | Verilog testbenches for individual modules and top-level integration.      |
| `build/`  | Python scripts used for automation, simulation, parsing, and benchmarking. |
| `logs/`   | Simulation logs, waveforms, and benchmark outputs.                         |

---

# Interactive Hardware Shell

Running

```bash
make
```

launches the interactive hardware testing environment.


# RTL Documentation

Each RTL module contains its own documentation under the `rtl/` directory.

The documentation focuses on the design rationale and implementation thought process rather than simply describing the ports. Further refinements and architectural details will continue to be added as the project evolves.


