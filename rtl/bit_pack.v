`timescale 1ns / 1ps

module bit_pack (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface
    input  wire        pack_en,      // Assert high to pack new bits
    input  wire        flush_en,     // Assert high to flush remaining bits (end of packet)
    
    // Data input
    input  wire [31:0] bits,         // Up to 32 bits to pack
    input  wire [5:0]  count,        // Number of valid bits in 'bits' (0 to 32)
    
    // RAM Memory Interface
    output reg  [31:0] ram_data,     // Data bus to out_ram
    output reg         ram_we,       // Write enable to out_ram
    output reg         packer_ready  // Ready to accept new data
);

    // -------------------------------------------------------------------------
    // Internal State Registers
    // -------------------------------------------------------------------------
    reg [63:0] shifter_reg;
    reg [6:0]  fill_reg;             // Tracks 0 to 64 bits internally

    // -------------------------------------------------------------------------
    // Step 1: Input Masking
    // -------------------------------------------------------------------------
    // Matches C: bits & ((1 << count) - 1)
    wire [31:0] clean_bits;
    assign clean_bits = (count == 0)  ? 32'b0 :
                        (count >= 32) ? bits  : 
                        (bits & ((32'h1 << count) - 1'b1));

    // -------------------------------------------------------------------------
    // Step 2: Bit Width Normalization & Alignment Calculations
    // -------------------------------------------------------------------------
    // Safely zero-extend tracking signals to 7-bits to prevent type-mismatch warnings
    wire [6:0] fill_7b  = {1'b0, fill_reg};
    wire [6:0] count_7b = {1'b0, count};

    // Calculate dynamic shifting metrics
    wire [6:0] empty_bits_before_add;
    wire [6:0] shift_amount;
    
    assign empty_bits_before_add = 7'd64 - fill_7b;
    assign shift_amount          = empty_bits_before_add - count_7b;

    // -------------------------------------------------------------------------
    // Step 3: 64-Bit Barrel Shifter Runway
    // -------------------------------------------------------------------------
    wire [63:0] clean_bits_64b;
    wire [63:0] shifted_new_bits;

    assign clean_bits_64b   = {32'b0, clean_bits};
    assign shifted_new_bits = clean_bits_64b << shift_amount;

    // -------------------------------------------------------------------------
    // Step 4: Merge Combinational Combinations
    // -------------------------------------------------------------------------
    wire [63:0] next_shifter;
    wire [6:0]  next_fill;

    assign next_shifter     = shifter_reg | shifted_new_bits;
    assign next_fill        = fill_reg + count_7b;


    // -------------------------------------------------------------------------
    // Step 5: Sequential Execution Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifter_reg  <= 64'b0;
            fill_reg     <= 7'b0;
            ram_data     <= 32'b0;
            ram_we       <= 1'b0;
            packer_ready <= 1'b1;
        end else begin
            ram_we <= 1'b0;

            if (flush_en && fill_reg > 0) begin
                ram_data     <= shifter_reg[63:32];
                $display("[BIT PACKER]  SHIFTER FLUSHED [PACKER WRITE] 0x%b\n", next_shifter[63:32]);
                ram_we       <= 1'b1;
                shifter_reg  <= 64'b0;
                fill_reg     <= 7'b0;
                packer_ready <= 1'b1;


            end else if (pack_en && count > 0) begin
                $display("[BIT PACKER] PACKER RECEIVED 0x%b (%0d bits)\n", clean_bits, count);

                if (next_fill >= 7'd32) begin

                    // Write upper 32-bit word out to memory space
                    ram_data    <= next_shifter[63:32];
                    $display("[BIT PACKER] SHIFTER OVERFLOWED [PACKER WRITE] 0x%b\n", next_shifter[63:32]);
                    ram_we      <= 1'b1;
                    
                    // Consume the written word and track remainder fractional bits
                    shifter_reg <= next_shifter << 32;
                    fill_reg    <= next_fill - 7'd32;

                end else begin
                    // Not enough bits collected to justify writing out yet
                    shifter_reg <= next_shifter;
                    fill_reg    <= next_fill;

                end
            end
        end
    end

endmodule