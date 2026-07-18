`timescale 1ns / 1ps

module tb_encoder();

    // -------------------------------------------------------------
    // 1. Parameter Definitions & Testbench Signals
    // -------------------------------------------------------------
    parameter DATA_WIDTH = 16;
    parameter ADDR_WIDTH = 10;
    parameter CLK_PERIOD = 10; // 100 MHz clock

    reg                    clk;
    reg                    rst_n;
    reg                    start;
    wire                   done;
    wire                   encoder_busy;

    reg  [ADDR_WIDTH-1:0]  start_addr;
    reg  [ADDR_WIDTH-1:0]  block_size;
    reg  [7:0]             optimal_k;

    wire [ADDR_WIDTH-1:0]  ram_addr;
    reg  [DATA_WIDTH-1:0]  ram_data;

    wire                   pack_en;
    wire                   flush_en;
    wire [31:0]            pack_bits;
    wire [5:0]             pack_count;
    reg                    packer_ready;

    // -------------------------------------------------------------
    // 2. Mock RAM Storage Setup
    // -------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mock_ram [0:31];

    // Simulate the Synchronous (Clocked) RAM Read Delay
    always @(posedge clk) begin
        ram_data <= mock_ram[ram_addr];
    end

    // -------------------------------------------------------------
    // 3. Unit Under Test (UUT) Instance
    // -------------------------------------------------------------
    encoder #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .done(done),
        .encoder_busy(encoder_busy),
        .start_addr(start_addr),
        .block_size(block_size),
        .optimal_k(optimal_k),
        .ram_addr(ram_addr),
        .ram_data(ram_data),
        .pack_en(pack_en),
        .flush_en(flush_en),
        .pack_bits(pack_bits),
        .pack_count(pack_count),
        .packer_ready(packer_ready)
    );

    // -------------------------------------------------------------
    // 4. Clock Generation
    // -------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------
    // 5. Test Driver Stimulus
    // -------------------------------------------------------------

    integer idx;

    initial begin
        $dumpfile("logs/dump.vcd");
        $dumpvars(0, tb_encoder);
        // Initialize Control Inputs
        rst_n        = 0;
        start        = 0;
        packer_ready = 1; // Bit packer is ready to consume
        start_addr   = 0;
        block_size   = 6; // Testing a block of 6 samples
        optimal_k    = 8'd2;

        // Clear Mock Storage
        
        for (idx = 0; idx < 32; idx = idx + 1) begin
            mock_ram[idx] = 16'd0;
        end

        // Populating Test Vector matching normal data and 32+ bit split anomaly
        mock_ram[0] = 16'd9;    // Normal: Q=2 (110), R=1 (01)  -> 5 bits
        mock_ram[1] = 16'd4;    // Normal: Q=1 (10),  R=0 (00)  -> 4 bits
        
        // --- THE CRITICAL EDGE CASE ANOMALY ---
        // 126 >> 2 = Q of 31. Unary length = 32 bits (31 ones, 1 zero). 
        // Remainder = 2 bits. Total = 34 bits. This forces the 2-cycle stall split!
        mock_ram[2] = 16'd126;  
        
        mock_ram[3] = 16'd14;   // Normal: Q=3 (1110), R=2 (10) -> 6 bits
        mock_ram[4] = 16'd1;    // Normal: Q=0 (0),    R=1 (01) -> 3 bits
        mock_ram[5] = 16'd7;    // Normal: Q=1 (10),   R=3 (11) -> 4 bits

        // Hold reset for 2 cycles
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // Assert Start Pulse
        $display("\n[TB] --- Starting Encoder Execution Loop ---");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for pipeline complete flag
        @(posedge done);
        #(CLK_PERIOD * 2);
        
        $display("[TB] --- Simulation Run Completed Successfully ---");
        $finish;
    end

    // -------------------------------------------------------------
    // 6. Automated Cycle Monitor & Output Validation Engine
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && encoder_busy) begin
            $display("Time: %0d | State: %b | RAM Addr Req: %d | RAM Data Latched: 0x%h", 
                     $time, uut.state, ram_addr, ram_data);
            
            if (pack_en) begin
                $display("   >>> PUSH BITSTREAM -> Count: %d | Bits: %b", pack_count, pack_bits);
                
                // Assert check to capture if your packer count rolls over / misinterprets data
                if (pack_count == 0) begin
                    $display("   ❌ [CRITICAL ERROR] Zero length bit-packet generated! Compression desync imminent.");
                end
                if (pack_count > 32) begin
                    $display("   ❌ [CRITICAL ERROR] Bus violation! Count %d exceeds maximum 32-bit width.", pack_count);
                end
            end
            
            if (flush_en) begin
                $display("   >>> [FLUSH TRIGGERED] Flushing remaining barrel shifter padding bits.");
            end
        end
    end

endmodule