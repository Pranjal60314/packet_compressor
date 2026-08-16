`timescale 1ns / 1ps

module encoder #(
    parameter SAMPLE_SIZE = 16,
    parameter ADDR_WIDTH  = 10
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    input  wire                  start,
    output reg                   done,
    output reg                   encoder_busy,

    input  wire [ADDR_WIDTH-1:0] start_addr,
    input  wire [ADDR_WIDTH-1:0] block_size,
    input  wire                  is_reference,
    input  wire [7:0]            optimal_k,

    output reg  [ADDR_WIDTH-1:0] ram_addr,
    input  wire [SAMPLE_SIZE-1:0] ram_data,

    output reg                   pack_en,
    output reg  [31:0]           pack_bits,
    output reg  [5:0]            pack_count,                                          
    input  wire                  packer_ready
);

    localparam IDLE           = 3'b000,
               PACK_K         = 3'b001,
               PACK_REFERENCE = 3'b101,
               STREAM         = 3'b011, 
               DONE           = 3'b100;

    reg [2:0]            state;
    reg [ADDR_WIDTH-1:0] samples_processed;
    reg                  anomaly_second_half;
    reg [SAMPLE_SIZE-1:0] ref_sample;

    wire [SAMPLE_SIZE-1:0] q;
    wire [SAMPLE_SIZE-1:0] r;
    wire [63:0]           unary_bits;
    wire [6:0]            unary_len;
    wire [63:0]           combined_bits;
    wire [6:0]            total_len;

    reg [31:0] anomaly_upper_bits;
    reg [5:0]  anomaly_rem_count;

    wire [ADDR_WIDTH-1:0] curr_sample_idx;
    assign curr_sample_idx = is_reference ? (samples_processed + 1'b1) : samples_processed;

    assign q = ram_data >> optimal_k;
    assign r = ram_data & ((1'b1 << optimal_k) - 1'b1);
                                                                                               
    assign unary_bits = (((64'd1 << q) - 64'd1) << 1);
    assign unary_len  = q + 1'b1;

    assign combined_bits = (unary_bits << optimal_k) | r;
    assign total_len     = unary_len + optimal_k;

    // Helper function to format binary string of arbitrary width (MSB to LSB)
    function [512:0] fmt_bits;
        input [63:0] val;
        input [6:0]  width;
        integer i;
        reg [512:0] str;
        begin
            str = "";
            for (i = width - 1; i >= 0; i = i - 1) begin
                str = {str, val[i] ? "1" : "0"};
            end
            fmt_bits = str;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            done                <= 1'b0;
            encoder_busy        <= 1'b0;
            ram_addr            <= 0;
            pack_en             <= 1'b0;
            pack_bits           <= 32'd0;
            pack_count          <= 6'd0;
            samples_processed   <= 0;
            anomaly_second_half <= 1'b0;
            ref_sample          <= {SAMPLE_SIZE{1'b0}};
        end else begin
            pack_en <= 1'b0;
            done    <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        encoder_busy        <= 1'b1;
                        samples_processed   <= 0;
                        anomaly_second_half <= 1'b0;
                        
                        if (is_reference)
                            ram_addr <= start_addr - 1'b1;
                        else
                            ram_addr <= start_addr;

                        state <= PACK_K;
                    end
                end

                PACK_K: begin
                    if (packer_ready) begin
                        pack_bits  <= {24'b0, optimal_k};
                        pack_count <= 6'd4;
                        pack_en    <= 1'b1;

                        //$display("[BIT PACK] Header (k=%0d)                 | Width:  4 bits | Hex: 0x%04X | Bits: %s", 
                        //         optimal_k, optimal_k[3:0], fmt_bits({60'b0, optimal_k[3:0]}, 4));
                        
                        if (is_reference) begin
                            ram_addr   <= start_addr;
                            state      <= PACK_REFERENCE;
                        end else begin
                            ram_addr   <= start_addr + 1'b1;
                            state      <= STREAM;
                        end
                    end
                end

                PACK_REFERENCE: begin
                    if (packer_ready) begin
                        pack_bits  <= { {(32-SAMPLE_SIZE){1'b0}}, ram_data };
                        pack_count <= 6'd16;
                        pack_en    <= 1'b1;

                        //$display("[BIT PACK] Reference Sample[0]          | Width: 16 bits | Hex: 0x%04X | Bits: %s", 
                        //         ram_data, fmt_bits({48'b0, ram_data}, 16));

                        ram_addr   <= start_addr + 1'b1;
                        state      <= STREAM;
                    end
                end

                STREAM: begin
                    if (packer_ready) begin
                        if (!anomaly_second_half) begin
                            pack_en <= 1'b1;

                            //$display("[BIT PACK] Sample[%0d] RAM DATA: %04X | Unary Q=%0d          | Width: %2d bits | Hex: 0x%04X | Bits: %s", 
                            //           curr_sample_idx, ram_data, q, unary_len, unary_bits[15:0], fmt_bits(unary_bits, unary_len));

                            if (optimal_k > 0) begin
                                //$display("[BIT PACK] Sample[%0d] RAM DATA: %04X | Remainder          | Width: %2d bits | Hex: 0x%04X | Bits: %s", 
                                //         curr_sample_idx, ram_data, optimal_k, r, fmt_bits({57'b0, r}, optimal_k));
                            end

                            if (total_len > 7'd32) begin
                                anomaly_rem_count   <= (total_len - 7'd32); 
                                pack_bits           <= combined_bits >> (total_len - 7'd32);
                                pack_count          <= 6'd32;
                                anomaly_upper_bits  <= combined_bits & ((64'd1 << (total_len - 7'd32)) - 64'd1); 
                                anomaly_second_half <= 1'b1; 
                            end else begin
                                pack_bits           <= combined_bits[31:0];
                                pack_count          <= total_len[5:0];
                                samples_processed   <= samples_processed + 1'b1;

                                if (samples_processed + 1'b1 >= block_size) begin
                                    state <= DONE;
                                end else begin
                                    ram_addr <= ram_addr + 1'b1;
                                end
                            end
                        end else begin
                            pack_en             <= 1'b1;
                            pack_bits           <= anomaly_upper_bits;
                            pack_count          <= anomaly_rem_count; 
                            anomaly_second_half <= 1'b0; 
                            samples_processed   <= samples_processed + 1'b1;

                            if (samples_processed + 1'b1 >= block_size) begin
                                state <= DONE;
                            end else begin
                                ram_addr <= ram_addr + 1'b1;
                            end
                        end
                    end
                end

                DONE: begin
                    if (packer_ready) begin
                        state        <= IDLE;
                        done         <= 1'b1;
                        encoder_busy <= 1'b0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule