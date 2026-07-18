`timescale 1ns / 1ps

module encoder #(
    parameter DATA_WIDTH = 16,
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
    input  wire [DATA_WIDTH-1:0] ram_data,

    output reg                   pack_en,
    output reg                   flush_en,
    output reg  [31:0]           pack_bits,
    output reg  [5:0]            pack_count, // Safely handles up to 32 bits per cycle
    input  wire                  packer_ready
);

    localparam IDLE         = 2'b00,
               SETUP_READ   = 2'b01,                                                           
               STREAM       = 2'b10, 
               FLUSH        = 2'b11;

    reg [1:0]            state;
    reg [ADDR_WIDTH-1:0] samples_processed;
    reg                  anomaly_second_half; // High when streaming the upper half of a 32+ bit code

    // 64-bit internal width to gracefully swallow anomalies
    wire [DATA_WIDTH-1:0] q;
    wire [DATA_WIDTH-1:0] r;
    wire [63:0]           unary_bits;
    wire [6:0]            unary_len;
    wire [63:0]           combined_bits;
    wire [6:0]            total_len;

    reg [31:0] anomaly_upper_bits;

    assign q = ram_data >> optimal_k;
    assign r = ram_data & ((1'b1 << optimal_k) - 1'b1);
                                                                                          
    // 64-bit safe shift operation
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
            flush_en            <= 1'b0;
            pack_bits           <= 32'd0;
            pack_count          <= 6'd0;
            samples_processed   <= 0;
            anomaly_second_half <= 1'b0;
        end else begin
            pack_en  <= 1'b0;
            flush_en <= 1'b0;
            done     <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        encoder_busy        <= 1'b1;
                        samples_processed   <= 0;
                        ram_addr            <= start_addr;
                        anomaly_second_half <= 1'b0;
                        state               <= SETUP_READ;
                    end
                end

                SETUP_READ: begin
                    ram_addr          <= ram_addr + 1'b1;
                    state             <= STREAM;
                end

                STREAM: begin
                    if (packer_ready) begin
                        if (!anomaly_second_half) begin
                            pack_en <= 1'b1;
                            if (total_len > 7'd32) begin
                                // 1. Send lower 32 bits immediately
                                pack_bits           <= combined_bits[31:0];
                                pack_count          <= 6'd32;
                                
                                // 2. SAVE the upper bits right now before ram_data changes!
                                anomaly_upper_bits  <= combined_bits[63:32];
                                anomaly_second_half <= 1'b1; 
                                
                                // 3. Freeze ram_addr so the RAM doesn't advance further
                                ram_addr            <= ram_addr; 
                            end else begin
                                // Normal single-cycle transmission
                                pack_bits           <= combined_bits[31:0];
                                pack_count          <= total_len[5:0];
                                samples_processed   <= samples_processed + 1'b1;
                                
                                if (samples_processed + 1'b1 >= block_size) begin
                                    state <= FLUSH;
                                end else begin
                                    ram_addr <= ram_addr + 1'b1;
                                end
                            end
                        end else begin
                            // --- SECOND HALF OF ANOMALY ---
                            pack_en             <= 1'b1;
                            
                            // Read from our safe registered holding buffer instead of the live wire
                            pack_bits           <= anomaly_upper_bits;
                            pack_count          <= (total_len - 7'd32);
                            
                            anomaly_second_half <= 1'b0; 
                            samples_processed   <= samples_processed + 1'b1;
                            if (samples_processed + 1'b1 >= block_size) begin
                                state <= FLUSH;
                            end else begin
                                ram_addr <= ram_addr + 1'b1;
                            end
                        end
                    end
                end

                FLUSH: begin
                    if (packer_ready) begin
                        flush_en     <= 1'b1;
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