import os
import pathfiles as pf
import helper as hp
import verilog_sim as vs

            
def print_help():
    print("\n" + "=" * 78)
    print("                 PACKET COMPRESSOR HARDWARE SHELL")
    print("=" * 78)

    print("\n GENERAL COMMANDS")
    print("  help")
    print("      Display this help menu.")
    print()
    print("  exit | quit")
    print("      Close the interactive shell.")
    print()
    print("  clean")
    print("      Remove generated simulation binaries, waveforms and log files.")
    print()

    print(" RTL SIMULATION")
    print("  tb <tb_name.v> [rtl_sources...]")
    print("      Compile and simulate a specific testbench.")
    print("      If no RTL sources are specified, all RTL modules are compiled.")
    print()
    print("      Example:")
    print("          tb tb_encoder.v")
    print("          tb tb_encoder.v encoder.v ram.v")
    print()
    print("  show <tb_name.v>")
    print("      Open the waveform generated for a testbench using GTKWave.")
    print("      Example:")
    print("          show tb_encoder.v")
    print()

    print(" SOFTWARE BENCHMARKING")
    print("  benchmark")
    print("      Run the reference C implementation against the configured")
    print("      telemetry datasets and generate compression statistics.")
    print("      Results are written to:")
    print("          logs/python_sim_log.txt")
    print("          logs/iteration_profiles.csv")
    print()

    print(" DATASET MANAGEMENT")
    print("  download")
    print("      Download the configured telemetry datasets and parse them")
    print("      into binary files suitable for benchmarking.")
    print()

    print(" INFORMATION")
    print("  list")
    print("      List all available testbenches present in the tb directory.")
    print()


def interactive_module():
    hp.setup_environment(purge_logs=False)
    print_help()

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
        
        elif command == "benchmark":
            compile_cmd = ["python3",os.path.join(pf.BUILD_DIR,"makefile_configs/pkt_test.py")]
            hp.run_stage("BENCHMARK",compile_cmd,"python")

        elif command == "download":
            compile_cmd = ["python3",os.path.join(pf.BUILD_DIR,"makefile_configs/kagg.py")]
            hp.run_stage("Downloading datasets", compile_cmd, "python")
            compile_cmd = ["python3",os.path.join(pf.BUILD_DIR,"makefile_configs/parser.py")]
            hp.run_stage("Parsing datasets", compile_cmd, "python")


        else:
            print(f" Unknown command: '{command}'. Type 'help' to see valid operations.")


if __name__ == "__main__":
    interactive_module()