#include <stdint.h>


uint8_t k_estimation(uint16_t *buffer, int block_size, bool is_reference) {

    uint32_t compression_length[8] = {0};

    for (int i = 0; i < block_size; i++) {
        uint16_t compression_sample = buffer[i];

        for (int j = 0; j < 9; j++) {
            uint32_t unchanged_bits = j;
            uint32_t changed_bits = (compression_sample >> j) + 1;
            compression_length[j] += (changed_bits + unchanged_bits);
        }
    }

    uint8_t optimal_k = 0;
    uint32_t min = compression_length[0];

    for (int i = 1; i < 8; i++) {
        if (compression_length[i] < min) {
            min = compression_length[i];
            optimal_k = i;
        }
    }

    printf("---->MIN:%u OPTMIAL K VALUE:%u\n", min, optimal_k);

    return optimal_k;
}