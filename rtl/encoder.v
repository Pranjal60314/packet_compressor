`timescale 1ns / 1ps

module encoder #(
    parameter SAMPLE_SIZE = 16,
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    input  wire                  start,
    output reg                   done,
    output reg                   encoder_busy,

    input  wire [ADDR_WIDTH-1:0] start_addr,
    input  wire [ADDR_WIDTH-1:0] block_size,
    input  wire [7:0]            optimal_k,

    output reg  [ADDR_WIDTH-1:0] ram_addr,
    input  wire [SAMPLE_SIZE-1:0] ram_data,

    output reg                   pack_en,
    output reg  [31:0]           pack_bits,
    output reg  [5:0]            pack_count,                                          
    input  wire                  packer_ready
);

    localparam IDLE         = 3'b000,
               PACK_K       = 3'b001,
               SETUP_READ   = 3'b010,                                                           
               STREAM       = 3'b011, 
               DONE         = 3'b100;

    // FIX 1: Expanded state width from [1:0] to [2:0] to fit DONE (3'b100)
    reg [2:0]            state;
    reg [ADDR_WIDTH-1:0] samples_processed;
    reg                  anomaly_second_half;                                                        

                                                            
    wire [SAMPLE_SIZE-1:0] q;
    wire [SAMPLE_SIZE-1:0] r;
    wire [63:0]           unary_bits;
    wire [6:0]            unary_len;
    wire [63:0]           combined_bits;
    wire [6:0]            total_len;

    reg [31:0] anomaly_upper_bits;
    reg [5:0]  anomaly_rem_count;

    assign q = ram_data >> optimal_k;
    assign r = ram_data & ((1'b1 << optimal_k) - 1'b1);
                                                                                               
    assign unary_bits = (((64'd1 << q) - 64'd1) << 1);
    assign unary_len  = q + 1'b1;

    assign combined_bits = (unary_bits << optimal_k) | r;
    assign total_len     = unary_len + optimal_k;

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
        end else begin
            pack_en  <= 1'b0;
            done     <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        encoder_busy        <= 1'b1;
                        samples_processed   <= 0;
                        ram_addr            <= start_addr;
                        anomaly_second_half <= 1'b0;
                        state               <= PACK_K;
                    end
                end

                // FIX 2 & 3: Added packer_ready check, updated count to 8 bits, and added transition to SETUP_READ
                PACK_K: begin
                    if (packer_ready) begin
                        pack_bits  <= {24'b0, optimal_k};
                        pack_count <= 6'd8; // 8-bit k header
                        pack_en    <= 1'b1;
                        state      <= SETUP_READ;
                        $display("[ENCODER] PACKING OPTIMAL_K: %8b PACK_COUNT: %4d\n",pack_bits,pack_count);
                    end
                end

                SETUP_READ: begin
                    ram_addr          <= ram_addr + 1'b1;
                    state             <= STREAM;
                end

                STREAM: begin
                    if (packer_ready) begin
                        $display("[ENCODER] PACKING BEGINS: \n");
                        if (!anomaly_second_half) begin
                            pack_en <= 1'b1;

                            if (total_len > 7'd32) begin
                                anomaly_rem_count   <= (total_len - 7'd32); 

                                pack_bits           <= combined_bits >> (total_len - 7'd32);
                                pack_count          <= 6'd32;

                                anomaly_upper_bits  <= combined_bits & ((64'd1 << (total_len - 7'd32)) - 64'd1); 
                                anomaly_second_half <= 1'b1; 

                                ram_addr            <= ram_addr; 

                                $display("[ENCODER] ANOMALY DETECTED WORD SIZE GREATER THAN 32\n");
                                $display("[ENCODER] PACK_BITS: %32b PACK_COUNT: %4d \n",pack_bits,pack_count);

                            end else begin
                                pack_bits           <= combined_bits[31:0];
                                pack_count          <= total_len[5:0];
                                samples_processed   <= samples_processed + 1'b1;

                                $display("[ENCODER] PACK_BITS: %32b PACK_COUNT: %4d\n",pack_bits, pack_count);

                                if (samples_processed + 1'b1 >= block_size) begin
                                    state <= DONE;
                                end else begin
                                    ram_addr <= ram_addr + 1'b1;
                                end
                            end
                        end else begin
                            // --- SECOND HALF OF ANOMALY ---
                            pack_en             <= 1'b1;
                            pack_bits           <= anomaly_upper_bits;
                            pack_count          <= anomaly_rem_count; 

                            anomaly_second_half <= 1'b0; 
                            samples_processed   <= samples_processed + 1'b1;

                            $display("[ENCODER] PROCESSING ANOMALY CARRYOVER PACK_BITS: %32b PACK_COUNT: %4d\n", pack_bits, pack_count);

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
                        $display("[ENCODER] ENCODER DONE ++++++++++++++++++++\n");
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