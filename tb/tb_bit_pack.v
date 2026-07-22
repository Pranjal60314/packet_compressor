`timescale 1ns / 1ps

module bit_packer_tb;

    // -------------------------------------------------------------------------
    // Testbench Clock & Stimulus Signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg         pack_en;
    reg         flush_en;
    reg  [31:0] bits;
    reg  [5:0]  count;

    wire [31:0] ram_data;
    wire        ram_we;
    wire        packer_ready;

    // -------------------------------------------------------------------------
    // Instantiate the Unit Under Test (UUT)
    // -------------------------------------------------------------------------
    bit_pack uut (
        .clk(clk),
        .rst_n(rst_n),
        .pack_en(pack_en),
        .flush_en(flush_en),
        .bits(bits),
        .count(count),
        .ram_data(ram_data),
        .ram_we(ram_we),
        .packer_ready(packer_ready)
    );

    // -------------------------------------------------------------------------
    // Clock Generator (100 MHz / 10ns period)
    // -------------------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Simple Memory Model to capture RAM writes
    // -------------------------------------------------------------------------
    reg [31:0] mock_ram [0:15];
    reg [3:0]  ram_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_addr <= 4'd0;
        end else if (ram_we) begin
            mock_ram[ram_addr] <= ram_data;
            $display("[RAM WRITE] Addr %0d <= 0x%h (Time: %0t)", ram_addr, ram_data, $time);
            ram_addr <= ram_addr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus Run
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("logs/tb_bit_pack_dump.vcd");
        $dumpvars(0, bit_packer_tb);
        // Initialize Signals
        clk      = 0;
        rst_n    = 0;
        pack_en  = 0;
        flush_en = 0;
        bits     = 32'b0;
        count    = 6'd0;

        // Reset Sequence
        #20;
        rst_n = 1;
        #10;
        
        $display("=== STARTING BIT PACKER TESTBENCH ===");

        // --- TEST 1: Pack exactly 32 bits (Should trigger an immediate RAM write) ---
        @(posedge clk);
        pack_en = 1'b1;
        bits    = 32'hABCDEF01;
        count   = 6'd32;
        
        @(posedge clk);
        pack_en = 1'b0; // Turn off to simulate a single cycle transaction
        
        // --- TEST 2: Accumulate smaller bit fragments ---
        @(posedge clk);
        pack_en = 1'b1;
        bits    = 32'hFFF_FAAA;
        count   = 6'd12;

        @(posedge clk);
        bits    = 32'h000_0BBB;
        count   = 6'd12;
        
        @(posedge clk);
        bits    = 32'h000_0CCC;
        count   = 6'd12;
        pack_en = 1'b1;
        

        @(posedge clk);//The value is stored into the shifter_reg and fill_reg, but no write yet
        @(posedge clk);//Now we turn the pack_en off to simulate a single cycle transaction since the write part is done simultaneously through the stored values and next we can try to flush the data which will already have flushed out a 32 bit word AAABBBCC
        pack_en = 1'b0;
        count   = 6'd0;

        // 4. Assert the flush command
         flush_en = 1'b1;
        
        // 5. Deassert flush command
        @(posedge clk);
        flush_en = 1'b0;

        #40;
        $display("=== TESTBENCH COMPLETE ===");
        $finish;
    end

endmodule