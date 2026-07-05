import os

#packet_generation.py                                                
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C_FILE_PATH = os.path.join(PROJECT_ROOT, "src", "pkten.c")
HEADER_PATH = os.path.join(PROJECT_ROOT, "src", "test_data.h")                                        
BUILD_DIR = os.path.join(PROJECT_ROOT, "build")
BINARY_PATH = os.path.join(PROJECT_ROOT,"src", "pkten_test")
LOG_PATH = os.path.join(PROJECT_ROOT, "logs", "sim_log.txt")
                                                          
os.makedirs(BUILD_DIR, exist_ok=True)
os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)

TELEMETRY_TEST_DIR = os.path.join(BUILD_DIR, "telemetry_test")
os.makedirs(TELEMETRY_TEST_DIR, exist_ok=True)

BASE_PARQUET_DIR = "/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/telemetry_test/"
BASE_OUTPUT_DIR = "/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/telemetry_test/"
