`timescale 1ns / 1ps

module top_level_tb; 
                                                                                
    parameter SAMPLE_SIZE    = 16;
    parameter ADDR_WIDTH     = 10;
    parameter PACKAGE_SIZE   = 4;
                                   
    localparam FILE_PATH     = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin"; 
    localparam TOTAL_SAMPLES = 160;
                                                                                
    reg                    clk;
    reg                    rst_n;
    reg                    packet_start;
    reg  [ADDR_WIDTH-1:0]  packet_sample_count;
    reg  [ADDR_WIDTH-1:0]  batch_size;
    reg  [ADDR_WIDTH-1:0]  package_size;

    wire [ADDR_WIDTH-1:0]  in_buf_addr;
    reg  [SAMPLE_SIZE-1:0]  in_buf_data;
    
    wire [31:0]            compressed_data;
    wire                    compressed_we;
    wire                    pipeline_done;

    reg [SAMPLE_SIZE-1:0]   mock_file_buffer [0:511];
                                                                                
    top_level #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .PACKAGE_SIZE(PACKAGE_SIZE)
    ) uut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .packet_start        (packet_start),
        .packet_sample_count (packet_sample_count),
        .batch_size          (batch_size),
        .package_size        (package_size),
        .in_buf_addr         (in_buf_addr),
        .in_buf_data         (in_buf_data),
        .compressed_data     (compressed_data),
        .compressed_we       (compressed_we),
        .pipeline_done       (pipeline_done)
    );
                                                                                
    always #5 clk = ~clk;                                    
                                                                                  
always @(*) begin
        in_buf_data = {mock_file_buffer[in_buf_addr][7:0], mock_file_buffer[in_buf_addr][15:8]};
        
        //$display("Input Buffer data: %h", in_buf_data);
    end
                               
    initial begin
        $dumpfile("logs/tb_top_level_dump.vcd");
        $dumpvars(0, top_level_tb);
    end
                            
    integer file_desc;                                                 

    initial begin
                            
        clk                 = 1'b0;
        rst_n               = 1'b0;
        packet_start        = 1'b0;
        packet_sample_count = TOTAL_SAMPLES; 
        batch_size          = 16;            
        package_size        = 64;            

        // OPEN AND READ THE RAW BINARY FILE PROPERLY
        file_desc = $fopen(FILE_PATH, "rb"); // "rb" means read binary
        if (file_desc == 0) begin
            $display("ERROR: Could not open binary file at %s", FILE_PATH);
            $finish;
        end
        
        // Read raw binary bytes straight into your 16-bit wide buffer
        $fread(mock_file_buffer, file_desc);
        $fclose(file_desc);

        // Standard System Reset Phase
        #40;
        rst_n = 1'b1;
        #20;
                               
        @(posedge clk);
        packet_start = 1'b1;
        
        @(posedge clk);
        packet_start = 1'b0;
                                                          
        fork
            begin : packet_monitor
                forever begin
                    @(posedge clk);
                    if (compressed_we) begin
                        $display("(Time: %0t ns) >> PACKED OUT TARGET WORD: 0x%b", $time, compressed_data);
                    end
                end
            end
            
            begin : termination_check
                                                                   
                @(posedge clk);
                wait(pipeline_done == 1'b1);
                
                #100;
                $display("\n=============================================");
                $display("SUCCESS: Processing of 160 samples complete!");
                $display("=============================================");
                disable packet_monitor;                                  
                $finish;
            end
        join
    end

                                             
endmodule