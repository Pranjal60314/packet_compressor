#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "bit_pack.c"
#include "k_estimat.c"
#include "delta_proc.c"
#include "helper.c"

                                                                       
// Force strict bit-by-bit unary packing to eliminate boundary gaps
void encode_unary(uint32_t quotient, uint64_t *shifter, uint8_t *fill, uint32_t **out_ram) {
    // If quotient is 2, (1U << 2) - 1 is 3 (binary 11). Shift left 1 to make it 110 (width 3)
    uint32_t unary_code = ((1U << quotient) - 1) << 1; 
    uint8_t unary_width = quotient + 1;

    bit_packer(unary_code, unary_width, shifter, fill, out_ram);
}

uint32_t decode_unary(uint64_t *shifter, uint8_t *fill, const uint32_t **in_ram) {
    uint32_t quotient = 0;
    // Read exactly 1 bit at a time until the terminating 0 is reached
    while (bit_unpacker(1, shifter, fill, in_ram) == 1) {
        quotient++;
    }
    return quotient;
}

void encoder(const uint16_t *input_buffer,
             uint16_t *last_sample,
             int block_size, 
             uint64_t *shifter_reg,
             uint8_t *fill_reg,
             bool is_reference,
             uint32_t **output_buffer) 
{
    uint16_t local_mapped_values[block_size];
    uint16_t track_sample = *last_sample;
                                      
    for (int i = 0; i < block_size; i++) {
        if (is_reference && i == 0) {
            local_mapped_values[i] = input_buffer[i];
            track_sample = input_buffer[i];
            printf("[ %1d ] REFERENCE BYTE: %8d  DELTA MAPPED VALUE: %16b  INPUT VALUE: %16b \n", i,input_buffer[i], local_mapped_values[i], input_buffer[i]);
        } else {
            local_mapped_values[i] = delta_processing(track_sample, input_buffer[i]);
            track_sample = input_buffer[i]; 
            printf("[ %1d ] REGULAR BYTE: %8d   DELTA MAPPED VALUE: %16b  INPUT VALUE: %16b \n", i,input_buffer[i], local_mapped_values[i], input_buffer[i]);                          
        }
    }

    *last_sample = track_sample;
    printf("TRACKING SAMPLE: %8d \n", track_sample);
                                                
    uint8_t optimal_k;
    if (is_reference) {
        optimal_k = k_estimation(&local_mapped_values[1], block_size - 1, true);
    } else {
        optimal_k = k_estimation(local_mapped_values, block_size, false);
    }
    printf("OPTMIAL K VALUE: %1d \n", optimal_k);

    bit_packer(optimal_k, 4, shifter_reg, fill_reg, output_buffer);
    printf("PACKED K \n");
                                                   
    if (is_reference) {                                                    
        bit_packer(local_mapped_values[0], 16, shifter_reg, fill_reg, output_buffer);
        printf("REFERENCE PACKED \n");
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
    printf("BITS PACKED MOVING ONTO THE NEXT PACKET \n");
}

void decoder(uint16_t *output_reconstructed_buffer,
             uint16_t *last_sample,
             int block_size,
             uint64_t *shifter_reg,
             uint8_t *fill_reg,
             bool is_reference,
             const uint32_t **input_bitstream)
{                                                           
    uint8_t optimal_k = bit_unpacker(4, shifter_reg, fill_reg, input_bitstream);
    printf("[ DECODER DEBUG ] Unpacked optimal_k = %4b\n", optimal_k);
    
    uint16_t local_mapped_values[block_size];
    int start_index = 0;
    
    if (is_reference) {
        local_mapped_values[0] = bit_unpacker(16, shifter_reg, fill_reg, input_bitstream);
        output_reconstructed_buffer[0] = local_mapped_values[0];
        printf("[ DECODER DEBUG ] Unpacked REFERENCE Sample[0] = %b\n", local_mapped_values[0]);
        *last_sample = local_mapped_values[0];
        start_index = 1;
    }
    
    for (int i = start_index; i < block_size; i++) {
        uint32_t quotient = decode_unary(shifter_reg, fill_reg, input_bitstream);
        uint32_t remainder = 0;
        if (optimal_k > 0) {
            remainder = bit_unpacker(optimal_k, shifter_reg, fill_reg, input_bitstream);
        }

        local_mapped_values[i] = (quotient << optimal_k) | remainder;                                                                      
        printf("[ DECODER DEBUG ] Unpacked Mapped Delta[%d] = %b\n", i, local_mapped_values[i]);
                                                                                 
        output_reconstructed_buffer[i] = inverse_delta_processing(*last_sample, local_mapped_values[i]); 
                                                                   
        *last_sample = output_reconstructed_buffer[i];
    }

    // FIX: Safely prints out the contents of the newly decoded block using the block_size parameter
    printf("[ DECODER DEBUG ] Current Reconstructed Block: ");
    //print_buffer(output_reconstructed_buffer, block_size);
}

int main(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <input_file.bin or -> <batch_size> <package_size>\n", argv[0]);
        return 1;
    }

    char *input_source = argv[1];
    int BATCH_SIZE = atoi(argv[2]);
    int PACKAGE_SIZE = atoi(argv[3]);

    FILE *file = NULL;
    bool is_stdin = (strcmp(input_source, "-") == 0);

    if (is_stdin) {
        file = stdin;
#ifdef _WIN32
        setmode(fileno(stdin), O_BINARY);
#endif
    } else {
        file = fopen(input_source, "rb");
        if (!file) {
            fprintf(stderr, "Error: Could not open file %s\n", input_source);
            return 1;
        }
    }

    // Allocate memory dynamically as chunks arrive from stdin or read from file
    size_t capacity = 4096;
    size_t total_samples = 0;
    uint16_t *dynamic_input = malloc(capacity * sizeof(uint16_t));
    
    if (!dynamic_input) {
        fprintf(stderr, "Error: Initial memory allocation failed\n");
        if (!is_stdin) fclose(file);
        return 1;
    }

    uint16_t temp_val;
    while (fread(&temp_val, sizeof(uint16_t), 1, file) == 1) {
        if (total_samples >= capacity) {
            capacity *= 2;
            uint16_t *new_ptr = realloc(dynamic_input, capacity * sizeof(uint16_t));
            if (!new_ptr) {
                fprintf(stderr, "Error: Memory realloc failed\n");
                free(dynamic_input);
                if (!is_stdin) fclose(file);
                return 1;
            }
            dynamic_input = new_ptr;
        }
        dynamic_input[total_samples++] = temp_val;
    }

    if (!is_stdin) {
        fclose(file);
    }

    if (total_samples == 0) {
        fprintf(stderr, "Error: No data read from input stream.\n");
        free(dynamic_input);
        return 1;
    }

    size_t file_size = total_samples * sizeof(uint16_t);
    uint16_t *decoded_output = malloc(file_size);
    if (!decoded_output) {
        fprintf(stderr, "Error: Memory allocation failed for decoded_output\n");
        free(dynamic_input);
        return 1;
    }

    if (total_samples % BATCH_SIZE != 0) {
        printf("[ WARNING ] File size is unaligned to BATCH_SIZE. Trailing chunks will be skipped.\n");
    }

    memset(decoded_output, 0, file_size);
                                            
    uint32_t output_ram[4096] = {0};                                         
    uint32_t *out_ptr = output_ram;
    uint64_t shifter = 0;
    uint8_t fill = 0;
    uint16_t running_history_sample = 0; 

    printf("[ CLI Engine ] Compression running on %zu samples...\n", total_samples);
                              
    int total_batches = total_samples / BATCH_SIZE;
    for (int batch_num = 0; batch_num < total_batches; batch_num++) {
        printf("\n\n\nCOMPRESSING BATCH [ %d ] \n", batch_num);
        uint16_t* current_buffer = dynamic_input + (batch_num * BATCH_SIZE);
        bool is_reference = (batch_num % PACKAGE_SIZE == 0);
        encoder(current_buffer, &running_history_sample, BATCH_SIZE, &shifter, &fill, is_reference, &out_ptr);
    }
    bit_packer_flush(&shifter, &fill, &out_ptr);
                                                                             
    ptrdiff_t words_written = out_ptr - output_ram;
    printf("[ CLI Engine ] Compression Finished. Occupies %td 32-bit words.\n", words_written);

    printf("[ CLI Engine ] Re-initializing Decoder loop verification...\n");
    printf("PRINTING OUTPUTARRAY FOR VERIFICATION : SIZE:[ %td ] \n", words_written);
    print_buffer_u32(output_ram, words_written);

    const uint32_t *in_decode_ptr = output_ram;
    uint64_t decode_shifter = 0;
    uint8_t decode_fill = 0;
    uint16_t decode_history_sample = 0;

    for (int batch_num = 0; batch_num < total_batches; batch_num++) {
        printf("\n[ DECODER ] PROCESSING BATCH [ %d ]\n", batch_num);
        uint16_t* target_reconstructed_buffer = decoded_output + (batch_num * BATCH_SIZE);
        bool is_reference = (batch_num % PACKAGE_SIZE == 0);
        decoder(target_reconstructed_buffer, &decode_history_sample, BATCH_SIZE, &decode_shifter, &decode_fill, is_reference, &in_decode_ptr);
    }

    bool is_bit_perfect = true;
    int total_processed_samples = total_batches * BATCH_SIZE;

    //print_pipeline_comparison(dynamic_input, decoded_output, total_processed_samples, output_ram, words_written);

    for (int i = 0; i < total_processed_samples; i++) {
        if (dynamic_input[i] != decoded_output[i]) {
            printf("[ ERROR ] Mismatch found at sample index [%d]! Sent: %u, Got: %u\n", i, dynamic_input[i], decoded_output[i]);
            is_bit_perfect = false;
            break;
        }
    }

    if (is_bit_perfect) {
        printf("[ SUCCESS ] Validation passed! Reconstructed stream matches input perfectly.\n");
    } else {
        printf("[ FAILED ] Data corruption detected in pipeline.\n");
    }

    free(dynamic_input);
    free(decoded_output);
    return is_bit_perfect ? 0 : -1;
}