import os
import sys
import subprocess
from datetime import datetime
import pathfiles as pf


def setup_environment(purge_logs=True):
                                                                 
    os.makedirs(pf.LOG_DIR, exist_ok=True)
    if purge_logs:
        for log_path in pf.LOGS.values():
            if os.path.exists(log_path):
                os.remove(log_path)
        print("[\033[92m+\033[0m] pf.PROJECT_ROOT target layout reset and logs purged.")


def run_stage(name, command, log_key):
                                                                                             
    print(f"\n[\033[94mExecuting Stage: {name}\033[0m] -> Using command: {' '.join(command)}")
    
    log_file_path = pf.LOGS[log_key]
    
    with open(log_file_path, "w", encoding="utf-8") as f:
        f.write(f"\n=== STAGE: {name} | EXECUTION TIME: {datetime.now()} ===\n")
        f.flush()

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1
        )

        assert process.stdout is not None

        while True:
            line = process.stdout.readline() 
            if not line and process.poll() is not None:
                break
            if line:
                sys.stdout.write(line)
                sys.stdout.flush()
                f.write(line)
                f.flush()

        return_code = process.wait()
        if return_code != 0:
            print(f"\n [\033[91mCRITICAL FAILURE\033[0m] Stage '{name}' terminated with code {return_code}")
            return False
        return True


def run_verilog_sim(tb_path, sources, output_bin, tb_name):
       
                                                                            
                                                                              
       
                                                 
    compile_cmd = ["iverilog", "-g2012", "-o", output_bin, f"-I{pf.RTL_DIR}"]
    compile_cmd.extend(sources)
    compile_cmd.append(tb_path)
    
                       
    if not run_stage("Verilog Compilation", compile_cmd, "rtl"):
        return False
        
                                  
    execute_cmd = ["vvp", output_bin]
    sim_success = run_stage("Verilog Simulation Run", execute_cmd, "rtl")

                                                                         
    if sim_success:
        target_vcd = os.path.join(pf.LOG_DIR, "dump.vcd")
        
        print("\n [\033[92mSimulation Success\033[0m] -> Launching Waveform Viewer automatically...")
        show_gtk(target_vcd)

    return sim_success


def show_gtk(target_vcd):
    if os.path.exists(target_vcd):
        print(f" Spawning GTKWave with: {os.path.basename(target_vcd)}")
        subprocess.Popen(["gtkwave", target_vcd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print(f"  Error: Waveform file not found at: {target_vcd}")
        print(f"    Ensure your testbench uses: $dumpfile(\"build/{os.path.basename(target_vcd)}\");")



def run(c_filepath):

    if not os.path.exists(c_filepath):
        print(f"  Error: Specified C verification file not found at: {c_filepath}")
        return

                                          
    output_exe = os.path.join(pf.LOG_DIR, "telemetry_test_exec")
    compile_cmd = ["gcc", "-O2", c_filepath, "-o", output_exe]
    
    if not run_stage("C Pipeline Compilation", compile_cmd, "rtl"):
        return

    print(f"\n [\033[92mCompilation Successful\033[0m] -> Commencing batch extraction across {len(pf.DATA_BINS)} files.")

                                                       
    for bin_file in pf.DATA_BINS:
        bin_path = os.path.join(pf.PROJECT_ROOT, "data", bin_file)                                     
        
        if not os.path.exists(bin_path):
            print(f"  Skipping: File target '{bin_file}' missing at expected path: {bin_path}")
            continue

        print(f"\n" + "-"*60)
        print(f" PROCESSING DATASTREAM: {bin_file}")
        print(f" Parameters -> Batch: {pf.TARGET_BATCH_SIZE} | Package: {pf.TARGET_PACKAGE_SIZE}")
        print(f"--------" + "-"*52)

                                                                                                        
        execute_cmd = [
            output_exe, 
            bin_path, 
            str(pf.TARGET_BATCH_SIZE), 
            str(pf.TARGET_PACKAGE_SIZE)
        ]
        
                                                                   
        run_stage(f"Processing Stream [{bin_file}]", execute_cmd, "rtl")

def print_help():
    print("\n" + "="*70)
    print("                AtmoLITE INTERACTIVE HARDWARE SHELL")
    print("="*70)
    print(" Commands available:")
    print("  tb <tb_name.v> [srcs...]  : Compile and simulate a specific testbench.")
    print("                              Example: tb tb_bit_packer.v bit_packer.v")
    print("  show <tb_name.v>          : Open GTKWave for a testbench's wave file.")
    print("  list                      : List all testbenches found in your RTL folder.")
    print("  run <c_file>              : Runs the specific c file as requested")
    print("  clean                     : Delete all compiled binary and log files.")
    print("  help                      : Display this menu.")
    print("  exit / quit               : Close the interactive simulation loop.")
    print("="*70 + "\n")


def interactive_module():
    setup_environment(purge_logs=False)
    print_help()

    while True:
        try:
            user_input = input("atmolite-sh > ").strip()
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
            setup_environment(purge_logs=True)
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
                    if f.endswith(".v") and not f.startswith("tb_")
                ]

            base_name = tb_name.replace(".v", "")
            output_bin = os.path.join(pf.LOG_DIR, f"{base_name}.vvp")

            print(f"\n [\033[94mPreparing {tb_name}\033[0m] -> Using {len(sources)} source file(s)")
            run_verilog_sim(tb_path, sources, output_bin, tb_name)
                    
                                                    
        elif command == "show":
            if len(args) < 1:
                print(" Error: Specify which testbench wave to open! Usage: show <tb_name.v>")
                continue
            
            tb_name = args[0].replace(".v", "")
            target_vcd = os.path.join(pf.LOG_DIR, f"{tb_name}.vcd")
            show_gtk(target_vcd)
        
        elif command == "run":
            if len(args) < 1:
                print(" Error: Missing filename parameter! Usage: run <c_file>")
                continue
            run(pf.SOURCE_DIR + "/" + args[0])

        else:
            print(f" Unknown command: '{command}'. Type 'help' to see valid operations.")


if __name__ == "__main__":
    interactive_module()