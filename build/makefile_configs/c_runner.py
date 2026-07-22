import os

import pathfiles as pf
import helper as hp

def run(c_filepath):

    if not os.path.exists(c_filepath):
        print(f"  Error: Specified C verification file not found at: {c_filepath}")
        return

    output_exe = os.path.join(pf.LOG_DIR, "telemetry_test_exec")
    compile_cmd = ["gcc", "-O2", c_filepath, "-o", output_exe]
    
    if not hp.run_stage("C Pipeline Compilation", compile_cmd, "rtl"):
        return

    print(f"\n [\033[92mCompilation Successful\033[0m] -> Commencing batch extraction across {len(pf.DATA_BINS)} files.")

    # 1. Clear out any residual stale contents from the target C simulation log file
    c_log_path = pf.LOGS["c"]
    with open(c_log_path, "w", encoding="utf-8") as f:
        f.write("============================================================\n")
        f.write("             AtmoLITE C CORE PIPELINE LOG DUMP              \n")
        f.write("============================================================\n\n")

    for bin_file in pf.DATA_BINS:
        bin_path = os.path.join(pf.TELEMETRY_TEST_DIR, bin_file)   
        
        if not os.path.exists(bin_path):
            print(f"  Skipping: File target '{bin_file}' missing at expected path: {bin_path}")
            continue

        print(f"\n" + "-"*60)
        print(f" PROCESSING DATASTREAM: {bin_file}")
        print(f" Parameters -> Batch: {pf.TARGET_BATCH_SIZE} | Package: {pf.TARGET_PACKAGE_SIZE}")
        print(f" Redirecting stdout console tracking to: {c_log_path}")
        print(f"--------" + "-"*52)

        # 2. Append processing context headers right inside the log file before executing
        with open(c_log_path, "a", encoding="utf-8") as log_file:
            log_file.write(f"\n\n" + "#"*80 + "\n")
            log_file.write(f" STREAM RUN TARGET: {bin_file}\n")
            log_file.write(f" Config Constants -> Batch: {pf.TARGET_BATCH_SIZE} | Package: {pf.TARGET_PACKAGE_SIZE}\n")
            log_file.write("#"*80 + "\n\n")

        execute_cmd = [
            output_exe, 
            bin_path, 
            str(pf.TARGET_BATCH_SIZE), 
            str(pf.TARGET_PACKAGE_SIZE)
        ]
        
        # 3. Handle redirection to your config file path wrapper context
        # If your 'hp.run_stage' wrapper accepts a stdout/stderr destination redirect, pass it there.
        # Otherwise, if 'hp.run_stage' only accepts standard string tracking flags (like "rtl"), 
        # you can temporarily modify the 'hp.run_stage' system invocation to capture output, OR
        # handle it natively right here via standard Python subprocess pipeline hooks:
        try:
            import subprocess
            # Natively launch the binary execution and divert output directly to the ASCII text log file
            with open(c_log_path, "a", encoding="utf-8") as log_file:
                subprocess.run(
                    execute_cmd, 
                    stdout=log_file, 
                    stderr=log_file, 
                    check=True, 
                    text=True
                )
            print(f" [\033[92mSUCCESS\033[0m] Stream [{bin_file}] logs successfully saved.")
        except subprocess.CalledProcessError as e:
            print(f" [\033[91mFAILURE\033[0m] Processing Stream [{bin_file}] exited with error code {e.returncode}")
        except Exception as e:
            print(f" [Error] An unexpected runtime pipeline failure occurred: {str(e)}")
