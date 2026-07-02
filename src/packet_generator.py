import random

array_size = 30

def generate_c_header_array(filename, array_size):
    random_numbers = [random.randint(1, 10) for _ in range(array_size)]
  
    lines = []
    for i in range(0, len(random_numbers), 10):
        chunk = random_numbers[i:i+10]
        chunk_str = ", ".join(str(num) for num in chunk)
        lines.append("    " + chunk_str)
        
    array_content = ",\n".join(lines)
    
    with open(filename, "w") as f:
        f.write("#ifndef TEST_DATA_H\n#define TEST_DATA_H\n\n")
        f.write(f"#define ARRAY_SIZE {array_size}\n\n")
        f.write(f"const uint16_t test_input[ARRAY_SIZE] = {{\n{array_content}\n}};\n\n")
        f.write("#endif\n")
        
    print(f"Generated C header file '{filename}' with a static array.")

generate_c_header_array("/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/src/test_data.h", array_size)


