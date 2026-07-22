import os
import pathfiles as pf
import helper as hp
import verilog_sim as vs
import c_runner as cr

            
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
    hp.setup_environment(purge_logs=False)
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
                    if f.endswith(".v") and not f.startswith("tb_")
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
        
        elif command == "run":
            if len(args) < 1:
                print(" Error: Missing filename parameter! Usage: run <c_file>")
                continue
            cr.run(pf.SOURCE_DIR + "/" + args[0])

        else:
            print(f" Unknown command: '{command}'. Type 'help' to see valid operations.")


if __name__ == "__main__":
    interactive_module()