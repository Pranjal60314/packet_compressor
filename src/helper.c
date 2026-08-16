#include <stdint.h>
#include <stddef.h>

void print_buffer(const uint16_t* array, int size){
    printf("[ ");
    for(int i = 0; i < size; i++){
        printf("%u ", array[i]);
    }
    printf("]\n");
}

void print_buffer_u32(const uint32_t* array, int size){
    printf("[ ");
    for(int i = 0; i < size; i++){
        printf("0x%08x ", array[i]);
    }
    printf("]\n");
}

void print_pipeline_comparison(const uint16_t *input, 
                               const uint16_t *decoded, 
                               int sample_count, 
                               const uint32_t *bitstream, 
                               ptrdiff_t words_written) 
{
    printf("\n========================================================================\n");
    printf("                  FULL PIPELINE VISUALIZATION HARNESS                   \n");
    printf("========================================================================\n");
    
    printf("\n[1] RAW BITSTREAM WORDS OCCUPIED (Size: %td words):\n", words_written);
    printf("------------------------------------------------------------------------\n");
    for (int i = 0; i < words_written; i++) {
        printf("Word [%03d]: 0x%08X  |  ", i, bitstream[i]);
        // Print bitstream word in binary format for bit-alignment checking
        for (int b = 31; b >= 0; b--) {
            printf("%d", (bitstream[i] >> b) & 1);
            if (b % 8 == 0 && b != 0) printf("_");
        }
        printf("\n");
    }

    printf("\n[2] SAMPLE TELEMETRY TIMELINE COMPARISON:\n");
    printf("------------------------------------------------------------------------\n");
    printf("%-12s | %-15s | %-15s | %-10s\n", "Index", "Input (Sent)", "Decoded (Got)", "Status");
    printf("------------------------------------------------------------------------\n");
    
    for (int i = 0; i < sample_count; i++) {
        bool match = (input[i] == decoded[i]);
        printf("Sample [%03d] | Value: %-8u | Value: %-8u | %s\n", 
               i, input[i], decoded[i], match ? "MATCH" : "CORRUPT [X]");
        
        // Truncate output print if it goes perfectly fine past 32 samples to save console space
        if (i == 31 && match) {
            // Find if there are errors further down the line
            int first_error = -1;
            for(int j = i + 1; j < sample_count; j++) {
                if(input[j] != decoded[j]) { first_error = j; break; }
            }
            if(first_error == -1) {
                printf("... [ Samples 32 to %d match perfectly, skipping lines ] ...\n", sample_count - 1);
                break;
            } else {
                printf("... [ Skipping to the first corrupt boundary at sample %d ] ...\n", first_error);
                i = first_error - 2; // Jump forward right before the error
            }
        }
    }
    printf("========================================================================\n\n");
}