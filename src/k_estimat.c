#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

uint16_t buffer[] = {1,1,1,1,1,1,1,1,1,1};

uint8_t k_estimation(uint16_t *buffer, int block_size, bool is_reference) {
    uint32_t compression_length[8] = {0};

    for (int i = 0; i < block_size; i++) {
        uint16_t compression_sample = i + 5;              //values being entered 
        for (int j = 0; j < 8; j++) {
            uint32_t unchanged_bits = j;
            uint32_t changed_bits = (compression_sample >> j) + 1;
            compression_length[j] += (changed_bits + unchanged_bits);
            printf("Compression Length K=%4d sample =%4d length=%4d\n",j,compression_sample,compression_length[j]);
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

    printf("---->MIN:%3d \n", min);

    return optimal_k;
}

int main(){
    return 0;
}