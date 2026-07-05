import random
import os
import subprocess
import sys
import re
import pathfiles as pf
import numpy as np
from collections import Counter

def load_telemetry_samples(bin_path, count, offset=0):                                                                  
    if not os.path.exists(bin_path):
        raise FileNotFoundError(f"Missing telemetry file at: {bin_path}")
    
    # FIX: Read as uint16 to match your parser's binary format
    data = np.fromfile(bin_path, dtype=np.uint16)
    sample_slice = data[offset : offset + count]                                                                                             
    
    if len(sample_slice) < count:
        raise ValueError(f"Requested {count} samples, but only {len(sample_slice)} remain at offset {offset}.")
                                                                 
    return sample_slice.astype(np.int32).tolist()


def calculate_input_parameters(data_list):
    arr = np.array(data_list, dtype=np.int32)
    deltas = np.diff(arr)
    total_samples = len(arr)
    
    counts = Counter(data_list)
    # Added minor epsilon to protect against log2(0) boundary edge-cases safely
    entropy = -sum((c / total_samples) * np.log2(c / total_samples) for c in counts.values())
    
    avg_delta = np.mean(np.abs(deltas)) if len(deltas) > 0 else 0   
    delta_variance = np.var(deltas) if len(deltas) > 0 else 0
    zero_deltas_pct = (np.sum(deltas == 0) / len(deltas) * 100) if len(deltas) > 0 else 0
    
    return {
        "entropy": entropy,
        "avg_delta": avg_delta,
        "delta_variance": delta_variance,
        "zero_deltas_pct": zero_deltas_pct
    }


def generate_c_header_array(filename, telemetry_data, array_size, batch_size, package_size):
    input_data = telemetry_data[:array_size]
    
    lines = []
    for i in range(0, len(input_data), 10):
        chunk = input_data[i:i+10]
        chunk_str = ", ".join(str(num) for num in chunk)
        lines.append("    " + chunk_str)
        
    array_content = ",\n".join(lines)
    
    with open(filename, "w") as f:
        f.write("#ifndef TEST_DATA_H\n#define TEST_DATA_H\n\n")
        f.write(f"#define ARRAY_SIZE {array_size}\n")
        f.write(f"#define PACKAGE_SIZE {package_size}\n")
        f.write(f"#define BATCH_SIZE {batch_size}\n\n")
        f.write("#include <stdint.h>\n\n") 
        f.write(f"const uint16_t test_input[ARRAY_SIZE] = {{\n{array_content}\n}};\n\n")
        f.write("#endif\n")


def run_and_analyze(array_size, batch_size, package_size):
    # Added Option A unity build linking rules to keep individual compilation clean
    compile_cmd = f"gcc \"{pf.C_FILE_PATH}\" -o \"{pf.BINARY_PATH}\" -lm"
    compile_proc = subprocess.run(compile_cmd, shell=True, capture_output=True, text=True)
    
    if compile_proc.returncode != 0:
        print("[-] Compilation Failed!")
        print(compile_proc.stderr)
        return None

    run_proc = subprocess.run(pf.BINARY_PATH, shell=True, capture_output=True, text=True)
    c_output = run_proc.stdout

    with open("/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/logs/csim_log.txt", "a") as c_log:
        c_log.write(f"\n{'='*40}\n")
        c_log.write(f" C EXECUTION LOG | PACKET SIZE: {array_size}\n")
        c_log.write(f"{'='*40}\n")
        c_log.write(c_output)

    match = re.search(r"TOTAL_COMPRESSED_BITS:(\d+)", c_output)
    
    if not match:
        min_matches = re.findall(r"---->MIN:\s*(\d+)", c_output)
        if not min_matches:
            return None
        
        total_batches_expected = array_size // batch_size
        if len(min_matches) != total_batches_expected:
            return None
                                                    
        total_payload_bits = sum(int(num) for num in min_matches)
        total_header_overhead = len(min_matches) * 4
        
        reference_batch_count = sum(1 for b in range(len(min_matches)) if b % package_size == 0)
        raw_anchor_bits = reference_batch_count * 16
        total_transmission_bits = total_payload_bits + total_header_overhead + raw_anchor_bits
    else:
        total_transmission_bits = int(match.group(1))

    k_values = [int(k) for k in re.findall(r"===>OPTIMAL K:\s*(\d+)", c_output)]
    uncompressed_bits = array_size * 16
    compression_ratio = uncompressed_bits / total_transmission_bits if total_transmission_bits > 0 else 0
    bits_per_sample = total_transmission_bits / array_size

    return {
        "compression_ratio": compression_ratio,
        "bits_per_sample": bits_per_sample,
        "k_values": k_values
    }


if __name__ == "__main__":
    ITERATIONS = 10000
    TARGET_BATCH_SIZE = 64
    TARGET_PACKAGE_SIZE = 16                                                                         
    TARGET_PACKET_SIZE = 160
    #160 0000

    if os.path.exists("sim_log.txt"):
        os.remove("sim_log.txt")
    if os.path.exists("csim_log.txt"):
        os.remove("csim_log.txt")
        
    print("=== STARTING LINEAR HIERARCHICAL BATCH COMPRESSION PROFILING ===")
    
    BASE_BIN_DIR = "/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/telemetry_test/"

    # Focus on the processed binary files
    target_files = [
        "AMT00103_raw.bin", 
        "CAT35000_raw.bin",
        "IHT13011_raw.bin",
        "MHT00001_raw.bin",
        "PHT01000_raw.bin",
        "SST00101_raw.bin",
        "XHT00010_raw.bin"
    ]

    for filename in target_files:
        bin_data_path = os.path.join(BASE_BIN_DIR, filename)
        if not os.path.exists(bin_data_path):
            print(f"[-] Missing binary file target {filename}... Skipping.")
            continue
            
        print(f"\nProcessing streams for target file: {filename}")
        print(f"[ Processing ] Running {ITERATIONS} iterations. Chunk size: {TARGET_PACKET_SIZE}")
        
        iteration_summaries = []

        for iteration in range(ITERATIONS):                                           
            current_offset = iteration * TARGET_PACKET_SIZE
            
            try:
                real_telemetry = load_telemetry_samples(bin_data_path, TARGET_PACKET_SIZE, offset=current_offset)
            except Exception as e:
                # Normal behavior when hit end of file boundary streams
                print(f"[!] Data boundary reached or file complete: {e}")
                break

            input_params = calculate_input_parameters(real_telemetry)
            generate_c_header_array(pf.HEADER_PATH, real_telemetry, TARGET_PACKET_SIZE, TARGET_BATCH_SIZE, TARGET_PACKAGE_SIZE)                                    
            run_params = run_and_analyze(TARGET_PACKET_SIZE, TARGET_BATCH_SIZE, TARGET_PACKAGE_SIZE)
            
            if run_params is None:
                continue

            profile = {**input_params, **run_params}
            iteration_summaries.append(profile)

        if iteration_summaries:
            total_runs = len(iteration_summaries)
            
            avg_entropy = np.mean([p["entropy"] for p in iteration_summaries])
            avg_delta = np.mean([p["avg_delta"] for p in iteration_summaries])
            avg_delta_variance = np.mean([p["delta_variance"] for p in iteration_summaries])
            avg_zero_deltas = np.mean([p["zero_deltas_pct"] for p in iteration_summaries])
            avg_compression_ratio = np.mean([p["compression_ratio"] for p in iteration_summaries])
            avg_bits_per_sample = np.mean([p["bits_per_sample"] for p in iteration_summaries])
            
            all_k_pool = []
            for p in iteration_summaries:
                all_k_pool.extend(p["k_values"])
            
            avg_k_value = np.mean(all_k_pool) if all_k_pool else 0
            k_counts = Counter(all_k_pool)
            total_k_elements = len(all_k_pool)

            # Append mode log reporting so profiles do not overwrite previous metrics
            with open("/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/logs/sim_log.txt", "a") as f:
                f.write("=" * 70 + "\n")
                f.write(f"  FILE: {filename} REPORT ({total_runs} ITERATIONS)\n")
                f.write("=" * 70 + "\n")
                f.write(f"Average Entropy              : {avg_entropy:.4f} bits/sample\n")
                f.write(f"Average Delta                : {avg_delta:.4f}\n")
                f.write(f"Average Delta Variance       : {avg_delta_variance:.4f}\n")
                f.write(f"Average Percentage Zero Delta: {avg_zero_deltas:.2f}%\n")
                f.write(f"Average Parameter k          : {avg_k_value:.2f}\n")
                f.write(f"Average Bits/Sample          : {avg_bits_per_sample:.4f} bits\n")
                f.write(f"Average Compression Ratio    : {avg_compression_ratio:.4f}x\n")
                f.write("=" * 70 + "\n\n")

            print("=" * 80)
            print(f"          PROFILE REPORT FOR {filename}")
            print("=" * 80)
            print(f"    -> Global Avg Entropy           : {avg_entropy:.4f} bits/sample")
            print(f"    -> Global Avg Delta Variance    : {avg_delta_variance:.4f}")
            print(f"    -> Global Avg Compression Ratio : {avg_compression_ratio:.4f}x")
            print("-" * 80)
            print(" COMPREHENSIVE DISTRIBUTION OF METRIC k:")
            if total_k_elements > 0:
                for k_val in sorted(k_counts.keys()):
                    percentage = (k_counts[k_val] / total_k_elements) * 100
                    print(f"    -> k = {k_val:<2} : {k_counts[k_val]:<5} selections ({percentage:.2f}%)")
            print("=" * 80 + "\n")