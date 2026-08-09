`timescale 1ns / 1ps

module ram_tb;

                 
    localparam SAMPLE_SIZE = 16;
    localparam ADDR_WIDTH  = 4;                                                 

              
    reg                   clk;
    reg                   we;
    reg  [ADDR_WIDTH-1:0] addr;
    reg  [SAMPLE_SIZE-1:0] din;
    wire [SAMPLE_SIZE-1:0] dout;

    integer errors = 0;

                                        
    ram #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) uut (
        .clk (clk),
        .we  (we),
        .addr(addr),
        .din (din),
        .dout(dout)
    );

                                                
    always #5 clk = ~clk;

                         
    initial begin
                                        
        $dumpfile("logs/tb_ram_dump.vcd");
        $dumpvars(0, ram_tb);

                            
        clk  = 0;
        we   = 0;
        addr = 0;
        din  = 0;

        #20;                                

        $display("==================================================");
        $display("           STARTING BRAM UNIT TEST                ");
        $display("==================================================");

                                                                       
                                                     
                                                                       
        $display("\n[TEST 1] Writing Data to Memory...");
        
        write_ram(4'h0, 16'hA1B2);
        write_ram(4'h1, 16'h3456);
        write_ram(4'h2, 16'h789A);
        write_ram(4'hF, 16'hFFFF);                

                                
        @(posedge clk);
        we <= 0;

                                                                       
                                                               
                                                                       
        $display("\n[TEST 2] Reading Back Data...");

        check_read_ram(4'h0, 16'hA1B2);
        check_read_ram(4'h1, 16'h3456);
        check_read_ram(4'h2, 16'h789A);
        check_read_ram(4'hF, 16'hFFFF);

                                                                       
                                                
                                                                       
        $display("\n[TEST 3] Testing Write Enable (WE = 0)...");
        
        @(posedge clk);
        we   <= 1'b0; // Disable write enable
        addr <= 4'h0;
        din  <= 16'hDEAD; // Try overwriting address 0

        @(posedge clk);
        // Address 0 should STILL contain 16'hA1B2
        check_read_ram(4'h0, 16'hA1B2);

                                                                       
                        
                                                                       
        #20;
        $display("\n==================================================");
        if (errors == 0) begin
            $display("   ALL TESTS PASSED SUCCESSFULLY!               ");
        end else begin
            $display("   TEST FAILED WITH %0d ERROR(S)                ", errors);
        end
        $display("==================================================\n");

        $finish;
    end

                                                                       
                         
                                                                       
    task write_ram(input [ADDR_WIDTH-1:0] w_addr, input [SAMPLE_SIZE-1:0] w_data);
        begin
            @(posedge clk);
            we   <= 1'b1;
            addr <= w_addr;
            din  <= w_data;
            $display("  [WRITE] Addr: 0x%0h | Data Written: 0x%04h", w_addr, w_data);
        end
    endtask

    // ----------------------------------------------------------------
    // Task: Read and Check RAM (Accounts for 1-Cycle Read Latency)
    // ----------------------------------------------------------------
    task check_read_ram(input [ADDR_WIDTH-1:0] r_addr, input [SAMPLE_SIZE-1:0] expected_data);
        begin
            // Cycle 1: Set address
            @(posedge clk);
            we   <= 1'b0;
            addr <= r_addr;

                                                                    
            @(posedge clk);
            #1;                                                 
            if (dout === expected_data) begin
                $display("  [READ PASS] Addr: 0x%0h | Expected: 0x%04h | Got: 0x%04h", r_addr, expected_data, dout);
            end else begin
                $display("  [READ FAIL] Addr: 0x%0h | Expected: 0x%04h | Got: 0x%04h", r_addr, expected_data, dout);
                errors = errors + 1;
            end
        end
    endtask

endmodule