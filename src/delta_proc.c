#include<stdint.h>

uint16_t delta_processing(uint16_t previous_x, uint16_t current_x) {
    int32_t delta_signed = (int32_t)current_x - (int32_t)previous_x;
    if (delta_signed >= 0) {
        return (uint16_t)delta_signed << 1;
    } else {
        return (uint16_t)(((-delta_signed) << 1) - 1);
    }
}


uint16_t inverse_delta_processing(uint16_t history, uint16_t mapped_delta) {
    int16_t signed_delta;
    if (mapped_delta & 1) {                                    
        signed_delta = -((mapped_delta + 1) >> 1);
    } else {                            
        signed_delta = (mapped_delta >> 1);
    }                                     
    return history + signed_delta;
}