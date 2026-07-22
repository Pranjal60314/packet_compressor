`timescale 1ns / 1ps

module tb_k_estimation;

    parameter SAMPLE_SIZE = 16;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [3:0]  block_size;
    reg  [3:0]  start_addr;
    
    wire        done;
    wire [7:0]  optimal_k;
    wire [31:0] min_length;
    wire [3:0]  mem_addr;
    wire [15:0] mem_data;

    // QUICK MATCH DATA: Generate the identical pattern using the address wire
    assign mem_data = mem_addr + 4'd5;

    // Instantiate Device Under Test
    k_estimation #(
        .SAMPLE_SIZE(SAMPLE_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .block_size(block_size),
        .start_addr(start_addr),
        .done(done),
        .optimal_k(optimal_k),
        .min_length(min_length),
        .mem_addr(mem_addr),
        .mem_data(mem_data)
    );

    // Clock Generation
    always #10 clk = ~clk;

    initial begin
        $dumpfile("logs/tb_k_estimat_dump.vcd");
        $dumpvars(0, tb_k_estimation);

        // Initialize signals
        clk        = 0;
        rst_n      = 0;
        start      = 0;
        block_size = 4'd0;
        start_addr = 4'd0;
        
        #40;
        rst_n = 1;
        #20;

        // Drive inputs matching C configuration
        @(posedge clk);
        start      <= 1'b1;
        block_size <= 4'd16;  
        start_addr <= 4'd0;   
        
        @(posedge clk);
        start      <= 1'b0;

        // Wait for done flag
        @(posedge done);
        #5; 
        
        $display("\n=====================================");
        $display("RTL SIMULATION OUTPUTS:");
        $display("Optimal K Hardware Output : %d", optimal_k);
        $display("Min Length Hardware Output: %d", min_length);
        $display("=====================================\n");

        #40;
        $finish;
    end

endmodule