#include<stdint.h>

uint16_t delta_processing(uint16_t previous_x, uint16_t current_x) {
    int32_t delta_signed = (int32_t)current_x - (int32_t)previous_x;
    if (delta_signed >= 0) {
        return (uint16_t)delta_signed << 1;
    } else {
        return (uint16_t)(((-delta_signed) << 1) - 1);
    }
}