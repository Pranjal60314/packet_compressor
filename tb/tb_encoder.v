`timescale 1ns / 1ps

module tb_encoder();               
                                                                    
    parameter SAMPLE_SIZE = 16;
    parameter ADDR_WIDTH = 10;
    parameter CLK_PERIOD = 10;                 

    reg                    clk;
    reg                    rst_n;
    reg                    start;
    wire                   done;
    wire                   encoder_busy;

    reg  [ADDR_WIDTH-1:0]  start_addr;
    reg  [ADDR_WIDTH-1:0]  block_size;
    reg  [7:0]             optimal_k;

    wire [ADDR_WIDTH-1:0]  ram_addr;
    reg  [SAMPLE_SIZE-1:0]  ram_data;

    wire                   pack_en;
    wire                   flush_en;
    wire [31:0]            pack_bits;
    wire [5:0]             pack_count;
    reg                    packer_ready;
                                                                    
    reg [SAMPLE_SIZE-1:0] mock_ram [0:31];
                  
    always @(posedge clk) begin
        ram_data <= mock_ram[ram_addr];
    end
                            
    encoder #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
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
        .pack_bits(pack_bits),
        .pack_count(pack_count),
        .packer_ready(packer_ready)
    );

                      
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer idx;

    initial begin
        $dumpfile("logs/dump.vcd");
        $dumpvars(0, tb_encoder);
                                    
        rst_n        = 0;
        start        = 0;
        packer_ready = 1;                                  
        start_addr   = 0;
        block_size   = 6;                                
        optimal_k    = 8'd2;

        // Clear Mock Storage
        
        for (idx = 0; idx < 32; idx = idx + 1) begin
            mock_ram[idx] = 16'd0;
        end

        mock_ram[0] = 16'd9;   
        mock_ram[1] = 16'd4; 
         
        mock_ram[2] = 16'd126;  
        
        mock_ram[3] = 16'd145;                                            
        mock_ram[4] = 16'd156;    
        mock_ram[5] = 16'd7;                                             

        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        $display("\n[TB] --- Starting Encoder Execution Loop ---");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        @(posedge done);
        #(CLK_PERIOD * 2);
        
        $display("[TB] --- Simulation Run Completed Successfully ---");
        $finish;
    end
              
    always @(posedge clk) begin
        if (rst_n && encoder_busy) begin
            $display("Time: %0d | State: %b | RAM Addr Req: %d | RAM Data Latched: 0x%h", 
                     $time, uut.state, ram_addr, ram_data);
            
            if (pack_en) begin
                $display("   >>> PUSH BITSTREAM -> Count: %d | Bits: %b", pack_count, pack_bits);
                
                                                                                               
                if (pack_count == 0) begin
                    $display("[CRITICAL ERROR] Zero length bit-packet generated! Compression desync imminent.");
                end
                if (pack_count > 32) begin
                    $display("[CRITICAL ERROR] Bus violation! Count %d exceeds maximum 32-bit width.", pack_count);
                end
            end
            
            if (flush_en) begin
                $display("   >>> [FLUSH TRIGGERED] Flushing remaining barrel shifter padding bits.");
            end
        end
    end

endmodule