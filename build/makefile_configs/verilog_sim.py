import os
import subprocess
import helper as hp
import pathfiles as pf

def run_verilog_sim(tb_path, sources, output_bin, tb_name):
                                                 
    compile_cmd = ["iverilog", "-g2012", "-o", output_bin, f"-I{pf.RTL_DIR}"]
    compile_cmd.extend(sources)
    compile_cmd.append(tb_path)
    
                       
    if not hp.run_stage("Verilog Compilation", compile_cmd, "rtl"):
        return False
        
                                  
    execute_cmd = ["vvp", output_bin]
    sim_success = hp.run_stage("Verilog Simulation Run", execute_cmd, "rtl")

                                                                         
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

