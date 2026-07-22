`timescale 1ns / 1ps

module delta_processing_tb;
                                                     
    reg  [15:0] previous_x;
    reg  [15:0] current_x;
    wire [15:0] encoded_delta;
                                                         
    delta_processing uut (
        .previous_x(previous_x),
        .current_x(current_x),
        .encoded_delta(encoded_delta)
    );      
                                                                                
    initial begin
        $dumpfile("logs/tb_delta_proc_dump.vcd");
        $dumpvars(0, delta_processing_tb);

        $display("=== STARTING DELTA PROCESSING TESTBENCH ===");

        previous_x = 16'd001;
        current_x  = 16'd001;
        #10;
        $display("[TEST 1] Prev: %d, Curr: %d | Encoded Delta: %d (Expected: 0)", previous_x, current_x, encoded_delta);
                              
        previous_x = 16'd001;
        current_x  = 16'd002;
        #10;
        $display("[TEST 2] Prev: %d, Curr: %d | Encoded Delta: %d (Expected: 2)", previous_x, current_x, encoded_delta);
                                         
        previous_x = 16'd002;
        current_x  = 16'd001;
        #10;
        $display("[TEST 3] Prev: %d, Curr: %d | Encoded Delta: %d (Expected: 1)", previous_x, current_x, encoded_delta);

        $display("=== TESTBENCH COMPLETE ===");
        $finish;
    end

endmodule