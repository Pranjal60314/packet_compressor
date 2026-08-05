import os
import pathfiles as pf # Assuming pathfiles defines pf.LOGS

def parse_and_route_simulation_log(raw_log_string):
    # Ensure all output directories exist before writing
    os.makedirs(os.path.dirname(pf.LOGS["rtl"]), exist_ok=True) # Base RTL log directory
    os.makedirs(os.path.dirname(pf.LOGS["k_estimate"]), exist_ok=True) # Submodule log directory
    os.makedirs(os.path.dirname(pf.LOGS["bit_packer"]), exist_ok=True) # Bit packer log directory

    # File handles dictionary
    file_handles = {
        "top"        : open(pf.LOGS["rtl"], "w"),
        "k_estimate" : open(pf.LOGS["k_estimate"], "w"),
        "encoder"    : open(pf.LOGS["encoder"], "w"),
        "bit_packer" : open(pf.LOGS["bit_packer"], "w"), # Re-purposed/routed appropriately
    }

    try:
        # Split log into individual lines
        for line in raw_log_string.strip().splitlines():
            line_str = line.strip()
            if not line_str:
                continue

            # Route by component prefix
            if "[K_ESTIMATOR]" in line_str or "OPTIMAL K" in line_str:
                file_handles["k_estimate"].write(line_str + "\n")

            elif "[ENCODER]" in line_str:
                file_handles["encoder"].write(line_str + "\n")

            elif "[BIT PACKER]" in line_str:
                file_handles["bit_packer"].write(line_str + "\n")

            else:
                # Top-level messages, VCD infos, and system execution times
                file_handles["top"].write(line_str + "\n")

    finally:
        # Guarantee all file handles close safely
        for fh in file_handles.values():
            fh.close()

    print("Successfully parsed and separated simulation logs into dedicated files!")

if __name__ == "__main__":
    # Example usage reading from log string or standard log output file
    with open(pf.LOGS["rtl"], "r") as f:
        raw_output = f.read()
    
    parse_and_route_simulation_log(raw_output)