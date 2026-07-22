import os

# ==============================================================================
# 1. CORE PIPELINE SIMULATION CONSTANTS
# ==============================================================================
ITERATIONS = 1000
TARGET_BATCH_SIZE = 16
TARGET_PACKAGE_SIZE = 2                                                                         
TARGET_PACKET_SIZE = 64

# ==============================================================================
# 2. DYNAMIC BASE ANCHORS
# ==============================================================================                                                
CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CONFIG_DIR, "..", ".."))

BUILD_DIR = os.path.join(PROJECT_ROOT, "build")
LOG_DIR = os.path.join(PROJECT_ROOT, "logs")
RTL_DIR = os.path.join(PROJECT_ROOT, "rtl")
SOURCE_DIR = os.path.join(PROJECT_ROOT,"src")
TB_DIR = os.path.join(PROJECT_ROOT,"tb")

# Ensure fundamental system paths exist immediately on import
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(BUILD_DIR, exist_ok=True)

# ==============================================================================
# 3. BUILD SCRIPTS MAP
# ==============================================================================
SCRIPTS = {
    "kagg":   os.path.join(BUILD_DIR, "kagg.py"),
    "parser": os.path.join(BUILD_DIR, "parser.py"),
    "test":   os.path.join(CONFIG_DIR, "pkt_test.py"),
}

# ==============================================================================
# 4. SOURCE FILE TESTING TRACKS
# ==============================================================================
C_FILE_PATH = os.path.join(PROJECT_ROOT, "src", "pkten.c")                                      
BINARY_PATH = os.path.join(PROJECT_ROOT, "src", "pkten_test")

# ==============================================================================
# 5. SIMULATION LOG TRACKING DUMPS
# ==============================================================================
LOGS = {
    "python": os.path.join(LOG_DIR, "python_sim_log.txt"),
    "rtl":    os.path.join(LOG_DIR, "rtl_sim_log.txt"),
    "c":      os.path.join(LOG_DIR, "c_sim_log.txt"),
    "rtl_output" : os.path.join(LOG_DIR, "sim.vvp"),
    "wave_dump"  : os.path.join(LOG_DIR, "wave.vcd"),
    "csv_file"   : os.path.join(LOG_DIR,"iteration_profiles.csv")
}

# ==============================================================================
# 6. RTL FILES AND TEST BENCHES
# ==============================================================================

RTL_FILES = {
    "bit_packer"        : f"{RTL_DIR}/bit_pack.v",
    "delta_processing"  : f"{RTL_DIR}/delta_proc.v",
    "k_estimator"       : f"{RTL_DIR}/k_estimat.v",
    "pkten"             : f"{RTL_DIR}/pkten.v"
}

TB_FILES = {
    "tb_bit_packer" : f"{TB_DIR}/tb_bit_pack.v",
    "tb_delta_processing" : f"{TB_DIR}/tb_delta_proc.v",
    "tb_k_estimator" : f"{TB_DIR}/tb_k_estimat.v",
    "tb_pkten" : f"{TB_DIR}/tb_pkt_en.v"
}


# ==============================================================================
# 6. DATA PARSING & PORTABLE TELEMETRY LAYOUT
# ==============================================================================
TELEMETRY_TEST_DIR = os.path.join(BUILD_DIR, "telemetry_test")
os.makedirs(TELEMETRY_TEST_DIR, exist_ok=True)

DATA_BINS = [
    "AMT00103_raw.bin", 
    "CAT35000_raw.bin",
    "IHT13011_raw.bin",
    "MHT00001_raw.bin",
    "PHT01000_raw.bin",
    "SST00101_raw.bin",
    "THT00006_raw.bin",
    "XHT00010_raw.bin"
]



def get_all_testbenches():
    import os
    try:
        return [f for f in os.listdir(RTL_DIR) if f.startswith("tb_") and f.endswith(".v")]
    except Exception:
        return []

    
