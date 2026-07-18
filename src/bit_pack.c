#include <stdint.h>
                                                                                                                                                                                                                                                                                                                                                                                                                                         
void bit_packer_flush(uint64_t *shifter_reg, uint8_t *fill_reg, uint32_t **output_buffer) {
    if (*fill_reg > 0) {
                                                                                   
                                                                               
        uint32_t final_word = (uint32_t)(*shifter_reg << (32 - *fill_reg));
        
                                                          
        **output_buffer = final_word;
        (*output_buffer)++;
        
                                             
        *shifter_reg = 0;
        *fill_reg = 0;
    }
}


                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                

void bit_packer(uint32_t value, uint8_t bits, uint64_t *shifter, uint8_t *fill, uint32_t **out_ram) {
                                                                            
    value &= (1ULL << bits) - 1;
    
                                                                                                 
    *shifter = (*shifter << bits) | value;
    *fill += bits;
    
                                                       
    while (*fill >= 32) {
        *fill -= 32;
        **out_ram = (uint32_t)(*shifter >> *fill);
        (*out_ram)++;
    }
}

uint32_t bit_unpacker(uint8_t bits, uint64_t *shifter, uint8_t *fill, const uint32_t **in_ram) {
                                                                   
    while (*fill < bits) {
        *shifter = (*shifter << 32) | **in_ram;
        (*in_ram)++;
        *fill += 32;
    }
    
                                                                   
    *fill -= bits;
    
                                                                               
    uint32_t value = (uint32_t)(*shifter >> *fill);
    
                                                    
    return value & ((1U << bits) - 1);
}
