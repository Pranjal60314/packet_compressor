import os
import zipfile
import kaggle
import pathfiles as pf

                               
TARGET_DIR = pf.TELEMETRY_TEST_DIR
os.makedirs(TARGET_DIR, exist_ok=True)

dataset_path = "patrickfleith/goce-satellite-telemetry"
target_files = [
    "AMT00103/AMT00103_raw.parquet", 
    "CAT35000/CAT35000_raw.parquet",
    "IHT13011/IHT13011_raw.parquet",
    "MHT00001/MHT00001_raw.parquet",
    "PHT01000/PHT01000_raw.parquet",
    "SST00101/SST00101_raw.parquet",
    "THT00006/THT00006_raw.parquet",
    "XHT00010/XHT00010_raw.parquet"
]

print(f"Starting downloads to: {TARGET_DIR}\n")

for file_route in target_files:
    pure_filename = file_route.split('/')[-1]                                        
    print(f"Processing: {pure_filename}...")
    
                                                                        
    try:
        kaggle.api.dataset_download_file(
            dataset_path,
            file_name=file_route,
            path=TARGET_DIR
        )
    except Exception as e:
        print(f"  [ERROR] Failed to download {pure_filename}: {e}")
        continue

                                                                
    zip_path = os.path.join(TARGET_DIR, f"{pure_filename}.zip")
    
    if os.path.exists(zip_path):
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                                                                           
                zip_ref.extractall(TARGET_DIR)
            print(f"  [SUCCESS] Extracted {pure_filename}")
            
                                                         
            os.remove(zip_path)
            print(f"  [CLEANUP] Deleted archive wrapper: {pure_filename}.zip")
            
        except Exception as e:
            print(f"  [ERROR] Problem processing zip file {zip_path}: {e}")
    else:
        print(f"  [WARNING] Expected zip file not found at: {zip_path}")

print("\nAll downloads, extractions, and workspace cleanups are complete!")
