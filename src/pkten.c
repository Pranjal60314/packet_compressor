#include <stdint.h>
#include <stdio.h>

#define BATCH_SIZE 16

#include "test_data.h"

/// @brief Packs bits into a 32-bit word and writes to the output stream when full
/// @param bits //the bits to pack
/// @param count //number of bits to pack
/// @param shifter //pointer to the shifter variable which captures bits before the writing happens
/// @param fill //pointer to the fill variable which tracks how many bits are currently in the shifter
/// @param out_ram //pointer to the output stream pointer
void bit_packer(uint32_t bits, uint8_t count, uint64_t *shifter, uint8_t *fill, uint32_t **out_ram) {
    
    if (count == 0) return;
    
    if (count < 32) {
        bits &= (1U << count) - 1;
    }
    
    *shifter |= ((uint64_t)bits << (64 - *fill - count));
    *fill += count;
    
    while (*fill >= 32) {
        uint32_t complete_word = (uint32_t)(*shifter >> 32);
        **out_ram = complete_word;
        (*out_ram)++;
        *shifter <<= 32;
        *fill -= 32;
    }
}

/// @brief Forces any remaining bits left over in the shifter to be written out to memory
void bit_packer_flush(uint64_t *shifter_reg, uint8_t *fill_reg, uint32_t **output_buffer) {
    if (*fill_reg > 0) {
        uint32_t final_word = (uint32_t)(*shifter_reg >> 32);
        **output_buffer = final_word;
        (*output_buffer)++;
        *shifter_reg = 0;
        *fill_reg = 0;
    }
}

/// @brief Encodes a unary value into the output stream
/// @param quotient //the unary value to encode
/// @param shifter //pointer to the shifter variable which captures bits before the writing happens
/// @param fill //pointer to the fill variable which tracks how many bits are currently in the shifter
/// @param out_ram //pointer to the output stream pointer
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

/// @brief Applies delta processing to a sample based on the previous sample
/// @param previous_x //pointer to the previous sample
/// @param current_x //current sample to be processed
/// @return delta-mapped value of the current sample
uint16_t delta_processing(uint16_t *previous_x, uint16_t current_x) {

    int32_t delta_signed = (int32_t)current_x - (int32_t)(*previous_x);
    uint16_t delta_mapped;

    if (delta_signed >= 0) {
        delta_mapped = (uint16_t)delta_signed << 1;
    } else {
        int32_t positive_delta = -delta_signed;
        delta_mapped = (uint16_t)((positive_delta << 1) - 1);
    }

    *previous_x = current_x;
    return delta_mapped;
}

/// @brief Estimates the optimal value of k for a block of samples
/// @param buffer //input buffer containing the block of samples
/// @param block_size //number of samples in the block
/// @return optimal value of k (0-7)
uint8_t k_estimation(uint16_t *buffer, int block_size) {

    uint32_t compression_length[8] = {0};

    for (int i = 0; i < block_size; i++) {
        uint16_t compression_sample = buffer[i];

        for (int j = 0; j < 8; j++) {
            uint32_t unchanged_bits = j;
            uint32_t changed_bits = (compression_sample >> j) + 1;
            compression_length[j] += (changed_bits + unchanged_bits);
        }
    }

    uint8_t optimal_k = 0;
    uint32_t min = compression_length[0];

    for (int i = 1; i < 8; i++) {
        if (min > compression_length[i]) {
            min = compression_length[i];
            optimal_k = i;
        }
    }

    return optimal_k;
}

/// @brief Encodes a block of samples using delta processing and unary encoding
void encoder(const uint16_t *input_buffer,
             uint16_t *last_sample,
             int block_size, 
             uint64_t *shifter_reg,
             uint8_t *fill_reg,
             uint32_t **output_buffer) 
{
    uint16_t local_deltas[block_size];

    for(int i = 0; i < block_size; i++){
        local_deltas[i] = delta_processing(last_sample, input_buffer[i]);
    }

    uint8_t optimal_k = k_estimation(local_deltas, block_size);

    bit_packer(optimal_k, 4, shifter_reg, fill_reg, output_buffer);

    for (int i = 0; i < block_size; i++) {
        uint16_t sample = local_deltas[i];
        uint32_t quotient = sample >> optimal_k;

        encode_unary(quotient, shifter_reg, fill_reg, output_buffer);

        if (optimal_k > 0) {
            uint32_t remainder = sample & ((1U << optimal_k) - 1);
            bit_packer(remainder, optimal_k, shifter_reg, fill_reg, output_buffer);
        }
    }
}

int main() {
    uint32_t output_ram[256];
    uint32_t *out_ptr = output_ram;

    uint64_t shifter = 0;
    uint8_t fill = 0;
    uint16_t last_sample = 0; 
    uint8_t batch_size = BATCH_SIZE;

    bit_packer(0, 4, &shifter, &fill, &out_ptr);
    if (ARRAY_SIZE >= BATCH_SIZE){

        for(int i = 0; i < BATCH_SIZE; i++){
            bit_packer(test_input[i], 16, &shifter, &fill, &out_ptr);
        }
    }

    last_sample = test_input[15];

    for(int byte_number = BATCH_SIZE; byte_number < ARRAY_SIZE; byte_number += BATCH_SIZE){
        
        batch_size = BATCH_SIZE;

        if(byte_number + BATCH_SIZE > ARRAY_SIZE){
            batch_size = ARRAY_SIZE - byte_number;
        }

        encoder(&test_input[byte_number], &last_sample, batch_size, &shifter, &fill, &out_ptr);
    }

    bit_packer_flush(&shifter, &fill, &out_ptr);

    for(int i=0; i< 10; i++){
        printf("Output: %16b \n",output_ram[i]);
    }

    return 0;
}