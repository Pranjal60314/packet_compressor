#include <stdint.h>

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

void bit_packer_flush(uint64_t *shifter_reg, uint8_t *fill_reg, uint32_t **output_buffer) {
    if (*fill_reg > 0) {
        uint32_t final_word = (uint32_t)(*shifter_reg >> 32);
        **output_buffer = final_word;
        (*output_buffer)++;
        *shifter_reg = 0;
        *fill_reg = 0;
    }
}
