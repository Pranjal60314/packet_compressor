#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#include "bit_pack.c"
#include "k_estimat.c"
#include "delta_proc.c"
                                                                                
#include "test_data.h"


void encode_unary(uint32_t quotient, uint64_t *shifter, uint8_t *fill, uint32_t **out_ram) {
    while (quotient >= 32) {
        bit_packer(0xFFFFFFFF, 32, shifter, fill, out_ram);
        quotient -= 32;
    }
    if (quotient > 0) {
        bit_packer((1U << quotient) - 1, quotient, shifter, fill, out_ram);
    }
    bit_packer(0, 1, shifter, fill, out_ram);
}
                                                                               
void encoder(const uint16_t *input_buffer,
             uint16_t *last_sample,
             int block_size, 
             uint64_t *shifter_reg,
             uint8_t *fill_reg,
             bool is_reference,
             uint32_t **output_buffer) 
{
    uint16_t local_mapped_values[BATCH_SIZE];
    uint16_t track_sample = *last_sample;
                                      
    for (int i = 0; i < block_size; i++) {
        if (is_reference && i == 0) {
                                                          
            local_mapped_values[i] = input_buffer[i];
            printf("==>REFERENCE SAMPLE CAPTURED: %16d  ---- INPUT_SAMPLE: %16d\n", local_mapped_values[i],input_buffer[i]);
            track_sample = input_buffer[i];                                   
        } else {
                                                                      
            local_mapped_values[i] = delta_processing(track_sample, input_buffer[i]);
            printf("===>REGULAR SAMPLE CAPTURED: %16d  ---- INPUT_SAMPLE: %16d\n", local_mapped_values[i],input_buffer[i]);
            track_sample = input_buffer[i];                           
        }
    }
                                                                 
    *last_sample = track_sample;
                                                
    uint8_t optimal_k = k_estimation(local_mapped_values, block_size, is_reference);
    printf("===>OPTIMAL K: %8d \n", optimal_k);
                                         
    bit_packer(optimal_k, 4, shifter_reg, fill_reg, output_buffer);
                                                   
    if (is_reference) {                                                    
        bit_packer(local_mapped_values[0], 16, shifter_reg, fill_reg, output_buffer);
    }
                                                             
    int start_index = is_reference ? 1 : 0;
    for (int i = start_index; i < block_size; i++) {
        uint16_t sample = local_mapped_values[i];
        uint32_t quotient = sample >> optimal_k;

        encode_unary(quotient, shifter_reg, fill_reg, output_buffer);

        if (optimal_k > 0) {
            uint32_t remainder = sample & ((1U << optimal_k) - 1);
            bit_packer(remainder, optimal_k, shifter_reg, fill_reg, output_buffer);
        }
    }
}

void print_buffer(const uint16_t* array, uint8_t size){
    printf("[ ");
    for(int i = 0; i < size; i++){
        printf("%u ", array[i]);
    }
    printf("]\n");
}

int main() {
    uint32_t output_ram[1024] = {0};
    uint32_t *out_ptr = output_ram;

    uint64_t shifter = 0;
    uint8_t fill = 0;
    uint16_t running_history_sample = 0; 
    printf("hi i am here\n");

    print_buffer(test_input, ARRAY_SIZE);

    int total_batches = ARRAY_SIZE / BATCH_SIZE;
    for (int batch_num = 0; batch_num < total_batches; batch_num++) {
        uint16_t* current_buffer = test_input + (batch_num * BATCH_SIZE);
        printf("[ + ] CURRENT_BUFFER: %16p \n [ + ] TEST_INPUT: %16p \n [ + ] JUMP: %16d -- %16td\n", 
       (void*)current_buffer, (void*)test_input, batch_num*BATCH_SIZE, current_buffer-test_input);
        print_buffer(current_buffer, BATCH_SIZE);
                                          
        bool is_reference = (batch_num % PACKAGE_SIZE == 0);
        
                                                        
        encoder(current_buffer, &running_history_sample, BATCH_SIZE, &shifter, &fill, is_reference, &out_ptr);
    }
    
    bit_packer_flush(&shifter, &fill, &out_ptr);
    return 0;
}