import os
import sys
import re
import subprocess
import gc
import csv                                      
import numpy as np
from collections import Counter
import pathfiles as pf

def load_telemetry_samples(bin_path, count, offset=0):                                                                  
    if not os.path.exists(bin_path):
        raise FileNotFoundError(f"Missing telemetry file at: {bin_path}")
    
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


def save_telemetry_chunk_bin(filename, telemetry_data):
                                                                                  
    arr = np.array(telemetry_data, dtype=np.uint16)
    arr.tofile(filename)


def compile_c_engine():
                                                                 
    print(f"[+] Compiling C engine: {pf.C_FILE_PATH} -> {pf.BINARY_PATH}")
    compile_cmd = f"gcc \"{pf.C_FILE_PATH}\" -o \"{pf.BINARY_PATH}\" -lm"
    compile_proc = subprocess.run(compile_cmd, shell=True, capture_output=True, text=True)
    
    if compile_proc.returncode != 0:
        print("[-] Compilation Failed!")
        print(compile_proc.stderr)
        return False
    return True


def run_and_analyze(telemetry_data, array_size, batch_size, package_size):
                                                                               
    arr_bytes = np.array(telemetry_data, dtype=np.uint16).tobytes()
    run_cmd = [pf.BINARY_PATH, "-", str(batch_size), str(package_size)]
    
    run_proc = subprocess.run(
        run_cmd, 
        input=arr_bytes,
        capture_output=True, 
        text=False
    )
    
                                                          
    c_output = run_proc.stdout.decode('utf-8', errors='replace')
    
                                                                       
    with open(pf.LOGS["c"], "w", encoding="utf-8") as c_log:
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

    k_values = [int(k) for k in re.findall(r"OPTMIAL K VALUE:\s*(\d+)", c_output)]
    uncompressed_bits = array_size * 16
    compression_ratio = uncompressed_bits / total_transmission_bits if total_transmission_bits > 0 else 0
    bits_per_sample = total_transmission_bits / array_size

    return {
        "compression_ratio": compression_ratio,
        "bits_per_sample": bits_per_sample,
        "k_values": k_values
    }

if __name__ == "__main__":
                                               
    for log_path in pf.LOGS.values():
        if os.path.exists(log_path):
            os.remove(log_path)
         
    csv_headers = [
        "Filename", "Iteration", "Offset", "Entropy", "Avg_Delta", 
        "Delta_Variance", "Zero_Deltas_Pct", "Compression_Ratio", 
        "Bits_Per_Sample", "Selected_K_Values"
    ]
                                       
    with open(pf.LOGS["csv_file"], mode="w", newline="", encoding="utf-8") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(csv_headers)

    TEMP_BIN_PATH = os.path.join(pf.BUILD_DIR, "temp_chunk.bin")
    if os.path.exists(TEMP_BIN_PATH):
        os.remove(TEMP_BIN_PATH)
        
    print("=== STARTING LINEAR HIERARCHICAL BATCH COMPRESSION PROFILING ===")
    
    if not compile_c_engine():
        sys.exit(1)
    
    target_files = {
        "AMT00103_raw.bin": "Magnetic Flux in Y of local CoF", 
        "CAT35000_raw.bin": "Acc. sensor head 1 raw acceleration x comp",
        "IHT13011_raw.bin": "Current TT thrust demand",
        "MHT00001_raw.bin": "Low Pressure Transducer",
        "PHT01000_raw.bin": "Analogue Voltage Sensor line",
        "SST00101_raw.bin": "Temperature_sensor",
        "XHT00010_raw.bin": "TRSP1 TX middle voltage of bridge between +6.3 V and -6.3 V"
    }

    for filename, description in target_files.items():
        bin_data_path = os.path.join(pf.TELEMETRY_TEST_DIR , filename)
        if not os.path.exists(bin_data_path):
            print(f"[-] Missing binary file target {filename}... Skipping.")
            continue
            
        print(f"\nProcessing target stream: {filename} ({description})")
        print(f"[ Processing ] Running {pf.ITERATIONS} iterations. Chunk size: {pf.TARGET_PACKET_SIZE}")
        
        iteration_summaries = []

        for iteration in range(pf.ITERATIONS):                                           
            current_offset = iteration * pf.TARGET_PACKET_SIZE
            
            try:
                real_telemetry = load_telemetry_samples(bin_data_path, pf.TARGET_PACKET_SIZE, offset=current_offset)
            except Exception as e:
                print(f"[!] Data boundary reached or file complete: {e}")
                break

            input_params = calculate_input_parameters(real_telemetry)
            
            run_params = run_and_analyze(
                real_telemetry, 
                pf.TARGET_PACKET_SIZE, 
                pf.TARGET_BATCH_SIZE, 
                pf.TARGET_PACKAGE_SIZE
            )
            
            if run_params is None:
                continue

            profile = {**input_params, **run_params}
            iteration_summaries.append(profile)
                                                                   
            k_string = ";".join(map(str, run_params["k_values"]))
            
            with open(pf.LOGS["csv_file"], mode="a", newline="", encoding="utf-8") as csv_file:
                writer = csv.writer(csv_file)
                writer.writerow([
                    filename,
                    iteration,
                    current_offset,
                    f"{input_params['entropy']:.4f}",
                    f"{input_params['avg_delta']:.4f}",
                    f"{input_params['delta_variance']:.4f}",
                    f"{input_params['zero_deltas_pct']:.2f}",
                    f"{run_params['compression_ratio']:.4f}",
                    f"{run_params['bits_per_sample']:.4f}",
                    k_string
                ])
            gc.collect()

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

            with open(pf.LOGS["python"], "a") as f:
                f.write("=" * 70 + "\n")
                f.write(f"  FILE: {filename} REPORT ({total_runs} ITERATIONS) : {description}\n")
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
            else:
                print("NO K COMPONENTS FOUND")
            print("=" * 80 + "\n")
            
    if os.path.exists(TEMP_BIN_PATH):
        os.remove(TEMP_BIN_PATH)
        
    print(f"[+] Profiling complete! You can open the Excel-ready sheet here:\n    -> {pf.LOGS["csv_file"]}")