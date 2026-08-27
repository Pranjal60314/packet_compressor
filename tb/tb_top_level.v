`timescale 1ns / 1ps

module top_level_tb; 

    parameter SAMPLE_SIZE    = 16;
    parameter ADDR_WIDTH     = 10;
    parameter PACKAGE_SIZE   = 4;
                                   
    localparam FILE_PATH = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin"; 
    localparam SAMPLES_PER_PACKET = 160;
    localparam TOTAL_SAMPLES = 1000;
    localparam TOTAL_PACKETS      = TOTAL_SAMPLES / SAMPLES_PER_PACKET;
                                                                                
    reg                    clk;
    reg                    rst_n;
    reg                    packet_start;
    reg  [ADDR_WIDTH-1:0]  packet_sample_count;
    reg  [ADDR_WIDTH-1:0]  batch_size;
    reg  [ADDR_WIDTH-1:0]  package_size;

    wire [ADDR_WIDTH-1:0]  in_buf_addr;
    reg  [SAMPLE_SIZE-1:0] in_buf_data;
    
    wire [31:0]            compressed_data;
    wire                   compressed_we;
    wire                   pipeline_done;

    // Buffer to hold up to 65536 16-bit samples
    reg [SAMPLE_SIZE-1:0]  mock_file_buffer [0:65535];
    integer                packet_offset;
    integer                pkt_idx;
    integer                file_desc, out_file;
                                                                                
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
                                                                                  
    // Endianness swap and streaming with dynamic packet offset
    always @(*) begin
        in_buf_data = {mock_file_buffer[packet_offset + in_buf_addr][7:0], 
                       mock_file_buffer[packet_offset + in_buf_addr][15:8]};
    end
                               
    initial begin
        $dumpfile("logs/tb_top_level_dump.vcd");
        $dumpvars(0, top_level_tb);
    end

    // File Logger: Capture only 32-bit packed hex words
    always @(posedge clk) begin
        if (compressed_we) begin
            $display("(Time: %0t ns) >> PACKED OUT TARGET WORD: 0x%08x", $time, compressed_data);
        end
    end

    initial begin
        clk                 = 1'b0;
        rst_n               = 1'b0;
        packet_start        = 1'b0;
        packet_sample_count = SAMPLES_PER_PACKET; 
        batch_size          = 16;            
        package_size        = 4;            
        packet_offset       = 0;

        // Open input binary
        file_desc = $fopen(FILE_PATH, "rb");
        if (file_desc == 0) begin
            $display("ERROR: Could not open binary file at %s", FILE_PATH);
            $finish;
        end
        $fread(mock_file_buffer, file_desc);
        $fclose(file_desc);

        // Reset Phase
        #40;
        rst_n = 1'b1;
        #20;

        // Multi-Packet Processing Loop
        for (pkt_idx = 0; pkt_idx < TOTAL_PACKETS; pkt_idx = pkt_idx + 1) begin
            packet_offset = pkt_idx * SAMPLES_PER_PACKET;
            $display("\n--- Starting Packet %0d / %0d (Sample Offset: %0d) ---", 
                     pkt_idx + 1, TOTAL_PACKETS, packet_offset);

            // Step 1: Pulse start for 1 cycle
            @(posedge clk);
            packet_start = 1'b1;
            @(posedge clk);
            packet_start = 1'b0;

            // Step 2: Ensure pipeline left resting state
            @(posedge clk);
            wait (pipeline_done == 1'b0);

            // Step 3: Wait for pipeline to return to resting state
            wait (pipeline_done == 1'b1);
            @(posedge clk);
            @(posedge clk);

            $display("--- Packet %0d Complete & Pipeline at Resting State ---", pkt_idx + 1);
        end

        $fclose(out_file);
        #50;
        $display("\n=============================================");
        $display("SUCCESS: All %0d packets processed!", TOTAL_PACKETS);
        $display("=============================================");
        $finish;
    end

endmodule