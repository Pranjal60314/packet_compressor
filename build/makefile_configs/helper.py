#environment setup and stage execution helper functions for the makefile
#stage execution works by calling the programs out by itself important for all other program running
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