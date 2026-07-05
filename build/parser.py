import os
import pandas as pd
import numpy as np
import pathfiles as pf
                                    

target_files = [
    "AMT00103_raw.parquet", 
    "CAT35000_raw.parquet",
    "IHT13011_raw.parquet",
    "MHT00001_raw.parquet",
    "PHT01000_raw.parquet",
    "SST00101_raw.parquet",
    "THT00006_raw.parquet",
    "XHT00010_raw.parquet"
]

for file_route in target_files:
                                                         
    current_parquet_path = os.path.join(pf.BASE_PARQUET_DIR, file_route)
    
    pure_filename = file_route.split('/')[-1]                                
    binary_filename = pure_filename.replace('.parquet', '.bin')
    current_output_bin_path = os.path.join(pf.BASE_OUTPUT_DIR, binary_filename)

    print(current_parquet_path)

    print("\n" + "="*50)
    print(f"Processing File: {pure_filename}")
    print("="*50)

    if not os.path.exists(current_parquet_path):
        print(f"[ERROR] File not found at: {current_parquet_path}. Skipping.")
        continue

    try:
        print("Loading telemetry data column...")
        df = pd.read_parquet(current_parquet_path, columns=['value'], engine='pyarrow')
        print(df.head())                                      
        print("Hi hello bye ")

        clean_stream = df['value'].dropna().to_numpy()
        total_samples = len(clean_stream)
        print(f"Extracted {total_samples} valid sequential samples.")

        if total_samples > 0:
                                                                                      
            min_val, max_val = clean_stream.min(), clean_stream.max()
            if max_val != min_val:
                scaled_data = ((clean_stream - min_val) / (max_val - min_val) * 65535).round()
                binary_data = scaled_data.astype(np.uint16)
            else:
                binary_data = np.zeros_like(clean_stream, dtype=np.uint16)

                                      
            binary_data.tofile(current_output_bin_path)

            print("--- Success! ---")
            print(f"Binary file generated: {current_output_bin_path}")
            print(f"File size: {os.path.getsize(current_output_bin_path)} bytes")
            print(f"First 5 raw uint16 values: {binary_data[:5]}")
        else:
            print("[WARNING] No valid data inside file to compress.")

    except Exception as e:
        print(f"[ERROR] Critical failure processing {pure_filename}: {e}")

    finally:
                                                                    
        if os.path.exists(current_parquet_path):
            os.remove(current_parquet_path)
            print(f"[CLEANUP] Deleted raw file: {current_parquet_path}")

print("\nProcessing complete! Your test folder now only contains production-ready .bin streams.")
