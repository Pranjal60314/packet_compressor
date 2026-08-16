import os
import sys
import re
import argparse
from typing import Dict, List, Optional, Union
import pathfiles as pf
import helper as hp
import verilog_sim as vs


def update_testbench_config(dataset_name: str, total_samples: int, packet_size: int, batch_size: int, package_size: int):
    
    tb_path =  os.path.join(pf.TB_DIR, "tb_top_level.v")

    if not tb_path:
        print(f"[-] Error: Testbench not found in {os.path.join(pf.TB_DIR, 'tb_top_level.v')}")
        return False, None

    raw_bin_path = os.path.join(pf.DATASET_DIR, dataset_name)

    if not os.path.exists(raw_bin_path):
        print(f"[-] Warning: Dataset file not found at {raw_bin_path}")

    with open(tb_path, "r") as f:
        content = f.read()

    # Safely update testbench localparams/parameters
    content = re.sub(r'localparam\s+FILE_PATH\s*=\s*"[^"]*";', f'localparam FILE_PATH = "{raw_bin_path}";', content)
    content = re.sub(r'localparam\s+TOTAL_SAMPLES\s*=\s*\d+;', f'localparam TOTAL_SAMPLES = {total_samples};', content)
    content = re.sub(r'localparam\s+SAMPLES_PER_PACKET\s*=\s*\d+;', f'localparam SAMPLES_PER_PACKET = {packet_size};', content)

    with open(tb_path, "w") as f:
        f.write(content)

    print(f"[\033[92m+\033[0m] Testbench configured: {os.path.basename(tb_path)}")
    return True, tb_path


def isolate_packet_blocks(
    source: Union[str, os.PathLike],
    include_headers: bool = False
) -> Dict[int, Dict[str, Union[int, str, List[str]]]]:
    """Isolates each packet section from a simulation log file."""
    if isinstance(source, (str, os.PathLike)) and os.path.exists(str(source)):
        with open(source, "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = str(source)

    pattern = re.compile(
        r'(--- Starting Packet\s+(?P<pkt_num>\d+)\s*/\s*(?P<total_pkts>\d+)\s*\(Sample Offset:\s*(?P<offset>\d+)\)\s*---)'
        r'(?P<body>.*?)'
        r'(--- Packet\s+(?P=pkt_num)\s+Complete[^\n]*)',
        re.DOTALL
    )

    extracted_packets = {}

    for match in pattern.finditer(content):
        pkt_num = int(match.group("pkt_num"))
        total_pkts = int(match.group("total_pkts"))
        offset = int(match.group("offset"))
        body = match.group("body").strip()

        isolated_str = f"{match.group(1)}\n{body}\n{match.group(5)}" if include_headers else body
        words = re.findall(r'PACKED OUT TARGET WORD:\s*(0x[0-9a-fA-F]{1,8})', body)
        if not words:
            words = re.findall(r'0x[0-9a-fA-F]{8}', body)

        normalized_words = [f"0x{int(w, 16):08x}" for w in words]

        extracted_packets[pkt_num] = {
            "packet_num": pkt_num,
            "total_packets": total_pkts,
            "offset": offset,
            "block_str": isolated_str,
            "words": normalized_words
        }

    return extracted_packets


def get_c_model_words(c_log_path: str) -> List[str]:
    """Reads the C simulation log and extracts normalized 32-bit hex words from the '[ 0x... ]' output array."""
    if not os.path.exists(c_log_path):
        print(f"[-] Error: C log file not found at {c_log_path}")
        return []

    with open(c_log_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    # Search for the bracketed output array line: [ 0x... ]
    for line in lines:
        line_clean = line.strip()
        if line_clean.startswith("[") and line_clean.endswith("]") and "0x" in line_clean:
            words = re.findall(r'0x[0-9a-fA-F]+', line_clean)
            if words:
                return [f"0x{int(w, 16):08x}" for w in words]

    # Fallback to multi-line search if not on a single line
    content = "".join(lines)
    bracket_match = re.search(r'\[\s*(0x[0-9a-fA-F]+(?:\s+0x[0-9a-fA-F]+)+)\s*\]', content, re.DOTALL)
    if bracket_match:
        words = re.findall(r'0x[0-9a-fA-F]+', bracket_match.group(1))
        return [f"0x{int(w, 16):08x}" for w in words]

    return []


def compare_packet(pkt_num: int, offset: int, hw_words: List[str], c_words: List[str]) -> bool:
    """Compares HW output words against C model words and logs the verdict."""
    mismatches = []
    min_len = min(len(hw_words), len(c_words))

    for idx in range(min_len):
        if hw_words[idx] != c_words[idx]:
            mismatches.append((idx, hw_words[idx], c_words[idx]))

    len_diff = len(hw_words) - len(c_words)

    if not mismatches and len_diff == 0:
        print(f"  [\033[92mPASS\033[0m] Packet {pkt_num:02d} (Offset: {offset:5d}) -> All {len(hw_words)} words match 100%")
        return True
    else:
        print(f"\n  [\033[91mFAIL\033[0m] Packet {pkt_num:02d} (Offset: {offset:5d}) -> HW: {len(hw_words)} words | C: {len(c_words)} words")
        if len_diff != 0:
            print(f"         Word count mismatch: HW has {abs(len_diff)} {'more' if len_diff > 0 else 'fewer'} words.")
        
        print(f"         {'Word Idx':<10}{'HW Output':<15}{'C Golden':<15}")
        print(f"         {'-'*38}")
        for idx, hw, c in mismatches[:8]:
            print(f"         {idx:<10}{hw:<15}{c:<15}")
        if len(mismatches) > 8:
            print(f"         ... and {len(mismatches) - 8} more mismatches.")
        print("")
        return False


def run_verification_pipeline(dataset_name: str, total_samples: int = 10000, packet_size: int = 160, batch_size: int = 16, package_size: int = 4):
    num_packets = total_samples // packet_size
    print(f"\n=======================================================")
    print(f"  [\033[94mSTARTING AUTO-VERIFICATION PIPELINE\033[0m] -> {dataset_name}")
    print(f"  Total Samples: {total_samples} | Packet Size: {packet_size} | Total Packets: {num_packets}")
    print(f"=======================================================\n")

    # 1. Clear old logs
    for old_log in ["rtl/rtl_sim_log.txt", "rtl_sim_log.txt", "hw_output.txt"]:
        p = os.path.join(pf.LOG_DIR, old_log)
        if os.path.exists(p):
            os.remove(p)

    # 2. Update Testbench parameters
    ok, tb_path = update_testbench_config(dataset_name, total_samples, packet_size, batch_size, package_size)
    if not ok:
        return

    # 3. Run Verilog Simulation
    sources = [os.path.join(pf.RTL_DIR, f) for f in os.listdir(pf.RTL_DIR) if f.endswith(".v")]
    tb_basename = os.path.basename(tb_path)
    output_bin = os.path.join(pf.LOG_DIR, tb_basename.replace(".v", ".vvp"))
    
    print("\n[\033[93m1/3\033[0m] Running Verilog Simulation...")
    vs.run_verilog_sim(tb_path, sources, output_bin, tb_basename)

    # 4. Locate RTL output log
    rtl_log_path = os.path.join(pf.LOG_DIR, "rtl/rtl_sim_log.txt")
    if not os.path.exists(rtl_log_path):
        rtl_log_path = os.path.join(pf.LOG_DIR, "rtl_sim_log.txt")

    if not os.path.exists(rtl_log_path):
        print(f"[-] Error: Could not locate RTL simulation log at {rtl_log_path}")
        return

    # 5. Isolate packets from RTL log
    all_packets = isolate_packet_blocks(rtl_log_path)
    total_packets = len(all_packets)

    if total_packets == 0:
        print(f"[-] No packet blocks found in {rtl_log_path}")
        return

    print(f"\n[\033[93m2/3\033[0m] Executing C Golden Model & Comparing Outputs...")
    print(f"[*] Found {total_packets} isolated packet(s) in RTL log.\n")

    profile_script = os.path.join(pf.BUILD_DIR, "makefile_configs/pkt_test_indi.py")
    if not os.path.exists(profile_script):
        profile_script = os.path.join(pf.BUILD_DIR, "pkt_test_indi.py")

    c_log_path = os.path.join(pf.LOG_DIR, "c_sim_log.txt")
    passed_count = 0
    failed_count = 0

    for pkt_num, pkt_info in sorted(all_packets.items()):
        offset = pkt_info["offset"]
        hw_words = pkt_info["words"]

        # Profile packet using C Model
        cmd = [
            sys.executable, profile_script,
            "--file", dataset_name,
            "--offset", str(offset),
            "--packet-size", str(packet_size),
            "--batch-size", str(batch_size),
            "--package-size", str(package_size)
        ]
        hp.run_stage(f"PROFILING PACKET {pkt_num} (Offset: {offset})", cmd, "python")

        # Extract words from C log
        c_words = get_c_model_words(c_log_path)
        if not c_words:
            print(f"[-] Error: Unable to read C model words for Packet {pkt_num}")
            failed_count += 1
            continue

        # Word-by-word comparison
        if compare_packet(pkt_num, offset, hw_words, c_words):
            passed_count += 1
        else:
            failed_count += 1

    # 6. Verification Summary
    print(f"\n---------------------- Verification Summary ----------------------")
    print(f"Total Packets Evaluated : {total_packets}")
    print(f"Passed Packets          : \033[92m{passed_count}\033[0m")
    print(f"Failed Packets          : \033[91m{failed_count}\033[0m")
    print(f"------------------------------------------------------------------\n")

    if failed_count == 0:
        print("\033[92m[+] SUCCESS: All hardware packets matched the C Golden Model 100%!\033[0m\n")
    else:
        print("\033[91m[-] FAILURE: One or more packets failed verification.\033[0m\n")


def create_verify_parser():
    """CLI Argument parser for auto-verification."""
    parser = argparse.ArgumentParser(description="Auto-verification parser", add_help=False)
    parser.add_argument("--file", type=str, required=True, help="Target binary telemetry file")
    parser.add_argument("--samples", type=int, default=10000, help="Total sample count (default: 10000)")
    parser.add_argument("--packet-size", type=int, default=160, help="Packet size (default: 160)")
    parser.add_argument("--batch-size", type=int, default=16, help="Batch size (default: 16)")
    parser.add_argument("--package-size", type=int, default=4, help="Package size (default: 4)")
    return parser


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Auto Verification Standalone Runner")
    parser.add_argument("--file", type=str, required=True, help="Target binary dataset file")
    parser.add_argument("--samples", type=int, default=10000, help="Total samples (default: 10000)")
    parser.add_argument("--packet-size", type=int, default=160, help="Packet size (default: 160)")
    parser.add_argument("--batch-size", type=int, default=16, help="Batch size (default: 16)")
    parser.add_argument("--package-size", type=int, default=4, help="Package size (default: 4)")
    
    args = parser.parse_args()
    run_verification_pipeline(
        dataset_name=args.file,
        total_samples=args.samples,
        packet_size=args.packet_size,
        batch_size=args.batch_size,
        package_size=args.package_size
    )