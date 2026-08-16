import os
import sys
import argparse
import pathfiles as pf
import helper as hp
import verilog_sim as vs
import pkt_test_indi as pkti
import auto_verify as av

def print_help():
    print("""
Usage: <command> [options]

Commands:
  help                    Show this menu.
  list                    List available testbenches.
  clean                   Remove build artifacts, logs, and waveforms.
  exit, quit              Exit the shell.

  tb <tb.v> [rtl...]      Compile and run simulation.
                          Examples:
                            tb tb_encoder.v
                            tb tb_encoder.v encoder.v ram.v
  show <tb.v>             Open simulation waveform in GTKWave.
                          Example:
                            show tb_encoder.v
  profile [options]       Profile a single telemetry chunk using the C model.
                          Options:
                            --file <name>         Binary telemetry file (required)
                            --offset <int>        Sample starting offset (default: 0)
                            --packet-size <int>   Number of samples (default from config)
                            --batch-size <int>    Batch size for compression
                            --package-size <int>  Package size for anchor frames
                          Examples:
                            profile --file AMT00103_raw.bin
                            profile --file AMT00103_raw.bin --offset 4096 --packet-size 2048
  verify [options]        Run multi-packet hardware simulation and verify against C golden model.
                          Options:
                            --file <name>         Binary dataset (required)
                            --samples <int>       Total samples (default: 10000)
                            --packet-size <int>   Packet size (default: 160)
                            --batch-size <int>    Batch size (default: 16)
                            --package-size <int>  Package size (default: 4)
                          Example:
                            verify --file AMT00103_raw.bin --samples 10000 --packet-size 160
  benchmark               Run C reference model against full dataset.
                          Logs: logs/python_sim_log.txt
                                logs/iteration_profiles.csv
  download                Fetch and parse telemetry datasets.
""")





def interactive_module():
    hp.setup_environment(purge_logs=False)
    print_help()
    verify_parser = av.create_verify_parser()

    profile_parser = pkti.create_profile_parser()

    while True:
        try:
            user_input = input("compressor-sh > ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting shell...")
            break

        if not user_input:
            continue

        parts = user_input.split()
        command = parts[0].lower()
        args = parts[1:]

        if command in ["exit", "quit"]:
            print("Goodbye!")
            break

        elif command == "help":
            print_help()

        elif command == "list":
            tbs = [f for f in os.listdir(pf.TB_DIR)]
            print("\nFound Testbenches in TB folder:")
            for tb in tbs:
                print(f"  - {tb}")
            print("")

        elif command == "clean":
            print("[+] Purging log files and binary outputs...")
            hp.setup_environment(purge_logs=True)
            if os.path.exists(pf.LOG_DIR):
                for file in os.listdir(pf.LOG_DIR):
                    if file.endswith(".vvp") or file.endswith(".vcd"):
                        os.remove(os.path.join(pf.LOG_DIR, file))
            print("[\033[92m+\033[0m] Workspace cleaned cleanly.")

        elif command == "tb":
            if len(args) < 1:
                print(" Error: Missing testbench name! Usage: tb <tb_name.v> [source_files...]")
                continue

            tb_name = args[0]
            tb_path = os.path.join(pf.TB_DIR, tb_name)

            if not os.path.exists(tb_path):
                print(f" Error: Testbench '{tb_name}' not found in {pf.TB_DIR}")
                continue

            if len(args) > 1:
                sources = [os.path.join(pf.RTL_DIR, s) for s in args[1:]]
            else:
                sources = [
                    os.path.join(pf.RTL_DIR, f) 
                    for f in os.listdir(pf.RTL_DIR) 
                    if f.endswith(".v")
                ]

            base_name = tb_name.replace(".v", "")
            output_bin = os.path.join(pf.LOG_DIR, f"{base_name}.vvp")

            print(f"\n [\033[94mPreparing {tb_name}\033[0m] -> Using {len(sources)} source file(s)")
            vs.run_verilog_sim(tb_path, sources, output_bin, tb_name)
                    
        elif command == "show":
            if len(args) < 1:
                print(" Error: Specify which testbench wave to open! Usage: show <tb_name.v>")
                continue
            
            tb_name = args[0].replace(".v", "")
            target_vcd = os.path.join(pf.LOG_DIR, f"{tb_name}_dump.vcd")
            vs.show_gtk(target_vcd)

        elif command == "profile":
            try:
                parsed_args = profile_parser.parse_args(args)
            except SystemExit:
                # Catch argparse default exit on missing args/bad flags to prevent closing interactive shell
                print(" Usage: profile --file <filename> [--offset 0] [--packet-size N] [--batch-size N] [--package-size N]")
                continue

            # Construct script execution command for single-chunk profiling script
            profile_script = os.path.join(pf.BUILD_DIR, "makefile_configs/pkt_test_indi.py")
            cmd = [sys.executable, profile_script, "--file", parsed_args.file, "--offset", str(parsed_args.offset)]

            if parsed_args.packet_size:
                cmd.extend(["--packet-size", str(parsed_args.packet_size)])
            if parsed_args.batch_size:
                cmd.extend(["--batch-size", str(parsed_args.batch_size)])
            if parsed_args.package_size:
                cmd.extend(["--package-size", str(parsed_args.package_size)])

            hp.run_stage("SINGLE CHUNK PROFILING", cmd, "python")

        elif command == "verify":
            try:
                parsed_args = verify_parser.parse_args(args)
            except SystemExit:
                print(" Usage: verify --file <filename.bin> [--samples 10000] [--packet-size 160] [--batch-size 16] [--package-size 4]")
                continue
            
            av.run_verification_pipeline(
                dataset_name=parsed_args.file,
                total_samples=parsed_args.samples,
                packet_size=parsed_args.packet_size,
                batch_size=parsed_args.batch_size,
                package_size=parsed_args.package_size
            )

        elif command == "benchmark":
            compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/pkt_test.py")]
            hp.run_stage("BENCHMARK", compile_cmd, "python")

        elif command == "download":
            compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/kagg.py")]
            hp.run_stage("Downloading datasets", compile_cmd, "python")
            compile_cmd = [sys.executable, os.path.join(pf.BUILD_DIR, "makefile_configs/parser.py")]
            hp.run_stage("Parsing datasets", compile_cmd, "python")

        else:
            print(f" Unknown command: '{command}'. Type 'help' to see valid operations.")


if __name__ == "__main__":
    interactive_module()