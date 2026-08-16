import os
import sys
import re
import subprocess
import gc
import csv                                      
import argparse
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


def compile_c_engine():
    print(f"[+] Compiling C engine: {pf.C_FILE_PATH} -> {pf.BINARY_PATH}")
    compile_cmd = f"gcc -g -fsanitize=address \"{pf.C_FILE_PATH}\" -o \"{pf.BINARY_PATH}\" -lm"
    compile_proc = subprocess.run(compile_cmd, shell=True, capture_output=True, text=True)
    
    if compile_proc.returncode != 0:
        print("[-] Compilation Failed!")
        if compile_proc.stderr:
            print(f"[-] Compiler Error Output:\n{compile_proc.stderr.strip()}")
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
    c_stderr = run_proc.stderr.decode('utf-8', errors='replace')
    
    # Write both stdout and stderr to the C log file
    with open(pf.LOGS["c"], "w", encoding="utf-8") as c_log:
        c_log.write(f"\n{'='*40}\n")
        c_log.write(f" C EXECUTION LOG | PACKET SIZE: {array_size}\n")
        c_log.write(f"{'='*40}\n")
        c_log.write("--- STDOUT ---\n")
        c_log.write(c_output)
        if c_stderr:
            c_log.write("\n--- STDERR ---\n")
            c_log.write(c_stderr)

    # Check if process terminated with an error code (crash, segfault, non-zero exit)
    if run_proc.returncode != 0:
        print(f"[-] C Engine process crashed/failed with exit code {run_proc.returncode}")
        if c_stderr.strip():
            print(f"[-] C Engine STDERR:\n{c_stderr.strip()}")
        return None

    match = re.search(r"TOTAL_COMPRESSED_BITS:(\d+)", c_output)
    
    if not match:
        min_matches = re.findall(r"---->MIN:\s*(\d+)", c_output)
        if not min_matches:
            print("[-] C Engine Error: No expected output markers ('TOTAL_COMPRESSED_BITS' or '---->MIN:') found.")
            if c_stderr.strip():
                print(f"[-] C Engine STDERR:\n{c_stderr.strip()}")
            return None
        
        total_batches_expected = array_size // batch_size
        if len(min_matches) != total_batches_expected:
            print(f"[-] C Engine Output Mismatch: Expected {total_batches_expected} batch matches, but got {len(min_matches)}.")
            if c_stderr.strip():
                print(f"[-] C Engine STDERR:\n{c_stderr.strip()}")
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


def create_profile_parser():
    """Helper parser for the single-chunk telemetry profiler command."""
    parser = argparse.ArgumentParser(prog="profile", description="Single Chunk Telemetry Profiler", add_help=False)
    parser.add_argument("--file", "-f", type=str, required=True, help="Target telemetry binary file.")
    parser.add_argument("--offset", "-o", type=int, default=0, help="Offset to read samples from.")
    parser.add_argument("--packet-size", "-ps", type=int, default=None, help="Total target packet size.")
    parser.add_argument("--batch-size", "-bs", type=int, default=None, help="Compression batch size.")
    parser.add_argument("--package-size", "-pks", type=int, default=None, help="Compression package size.")
    return parser


def main():
    parser = argparse.ArgumentParser(description="Single-Chunk Telemetry Compression Profiler")
    parser.add_argument("--file", type=str, required=True, help="Path or filename of the telemetry binary.")
    parser.add_argument("--offset", type=int, default=0, help="Sample offset to start reading from.")
    parser.add_argument("--packet-size", type=int, default=pf.TARGET_PACKET_SIZE, help="Number of samples to process.")
    parser.add_argument("--batch-size", type=int, default=pf.TARGET_BATCH_SIZE, help="Batch size for compression engine.")
    parser.add_argument("--package-size", type=int, default=pf.TARGET_PACKAGE_SIZE, help="Package size for compression engine.")
    
    args = parser.parse_args()

    # Resolve file path
    bin_path = args.file if os.path.isabs(args.file) else os.path.join(pf.TELEMETRY_TEST_DIR, args.file)
    filename = os.path.basename(bin_path)

    # Initialize CSV header if file doesn't exist yet
    if not os.path.exists(pf.LOGS["csv_file"]):
        csv_headers = [
            "Filename", "Offset", "Entropy", "Avg_Delta", 
            "Delta_Variance", "Zero_Deltas_Pct", "Compression_Ratio", 
            "Bits_Per_Sample", "Selected_K_Values"
        ]
        with open(pf.LOGS["csv_file"], mode="w", newline="", encoding="utf-8") as csv_file:
            csv.writer(csv_file).writerow(csv_headers)

    print("=== SINGLE TELEMETRY BATCH COMPRESSION PROFILING ===")
    
    if not compile_c_engine():
        sys.exit(1)

    print(f"\nProcessing stream target: {filename}")
    print(f"[ Processing ] Offset: {args.offset} | Chunk size: {args.packet_size}")

    try:
        real_telemetry = load_telemetry_samples(bin_path, args.packet_size, offset=args.offset)
    except Exception as e:
        print(f"[-] Error loading telemetry data: {e}")
        sys.exit(1)

    input_params = calculate_input_parameters(real_telemetry)
    run_params = run_and_analyze(real_telemetry, args.packet_size, args.batch_size, args.package_size)

    if run_params is None:
        print("[-] C Engine analysis failed.")
        sys.exit(1)

    # Append single run result to CSV
    k_string = ";".join(map(str, run_params["k_values"]))
    with open(pf.LOGS["csv_file"], mode="a", newline="", encoding="utf-8") as csv_file:
        csv.writer(csv_file).writerow([
            filename,
            args.offset,
            f"{input_params['entropy']:.4f}",
            f"{input_params['avg_delta']:.4f}",
            f"{input_params['delta_variance']:.4f}",
            f"{input_params['zero_deltas_pct']:.2f}",
            f"{run_params['compression_ratio']:.4f}",
            f"{run_params['bits_per_sample']:.4f}",
            k_string
        ])

    # Display Metrics & Parameter K distribution
    k_counts = Counter(run_params["k_values"])
    total_k_elements = len(run_params["k_values"])

    print("\n" + "=" * 80)
    print(f"          SINGLE RUN PROFILE REPORT FOR {filename}")
    print("=" * 80)
    print(f"    -> Entropy               : {input_params['entropy']:.4f} bits/sample")
    print(f"    -> Avg Delta             : {input_params['avg_delta']:.4f}")
    print(f"    -> Delta Variance        : {input_params['delta_variance']:.4f}")
    print(f"    -> Compression Ratio     : {run_params['compression_ratio']:.4f}x")
    print(f"    -> Bits/Sample           : {run_params['bits_per_sample']:.4f} bits")
    print("-" * 80)
    print(" METRIC k DISTRIBUTION:")
    if total_k_elements > 0:
        for k_val in sorted(k_counts.keys()):
            percentage = (k_counts[k_val] / total_k_elements) * 100
            print(f"    -> k = {k_val:<2} : {k_counts[k_val]:<5} selections ({percentage:.2f}%)")
    else:
        print("NO K COMPONENTS FOUND")
    print("=" * 80 + "\n")

if __name__ == "__main__":
    main()