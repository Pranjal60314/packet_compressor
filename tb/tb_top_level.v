`timescale 1ns / 1ps

module top_level_tb;

    // -------------------------------------------------------------------------
    // Parameters & File Configurations
    // -------------------------------------------------------------------------
    parameter SAMPLE_SIZE    = 16;
    parameter ADDR_WIDTH     = 10;
    parameter PACKAGE_SIZE   = 4;
    
    // Replace this string with the actual path to your binary text data file
    localparam FILE_PATH     = "/home/pythonofapollo/WorkSpace/Active/AtmoLITE_packet_compressor/build/telemetry_test/AMT00103_raw.bin"; 
    localparam TOTAL_SAMPLES = 160;

    // -------------------------------------------------------------------------
    // Testbench Wire/Register Interfaces
    // -------------------------------------------------------------------------
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

    // Simulated file storage block array
    reg [SAMPLE_SIZE-1:0]   mock_file_buffer [0:511];

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Clock Generation Logic
    // -------------------------------------------------------------------------
    always #5 clk = ~clk; // 100MHz Clock simulation loop

    // -------------------------------------------------------------------------
    // ROM Dynamic Data Assignment
    // -------------------------------------------------------------------------
    // Dynamically feed data to the module as it changes its memory read addresses
    always @(*) begin
        in_buf_data = mock_file_buffer[in_buf_addr];
        $display("Input BUffer data: %b", in_buf_data);
    end

    // -------------------------------------------------------------------------
    // Waveform Capture Hook (Matches 'dump.vcd' standard configuration)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("logs/dump.vcd");
        $dumpvars(0, top_level_tb);
    end

    // -------------------------------------------------------------------------
    // Verification Procedures
    // -------------------------------------------------------------------------
    integer file_desc; // File descriptor handle for raw binary loading

    initial begin
        // Initialize inputs
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
        // Note: Make sure the file endianness matches your expected format!
        $fread(mock_file_buffer, file_desc);
        $fclose(file_desc);

        // Standard System Reset Phase
        #40;
        rst_n = 1'b1;
        #20;

        // Kickoff Packet compressing session
        @(posedge clk);
        packet_start = 1'b1;
        
        @(posedge clk);
        packet_start = 1'b0;

        // Monitor outputs to print compressed frames to terminal window console
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
                // Standby until structural state machine completes
                @(posedge clk);
                wait(pipeline_done == 1'b1);
                
                #100;
                $display("\n=============================================");
                $display("SUCCESS: Processing of 160 samples complete!");
                $display("=============================================");
                disable packet_monitor; // Halt logging print loop safely
                $finish;
            end
        join
    end

    // Replace $monitor with this clocked logging block
    always @(posedge clk) begin
        if (uut.stg1_ram_we) begin
            $display("[DELTA PROC] Time: %0t ns | PkgCnt: %0d | PREV: %16b | CURR: %16b | OUT_DELTA: %16b %s",
                     $time,
                     uut.package_sample_counter,
                     uut.delta_unit.previous_x,
                     uut.delta_unit.current_x,
                     uut.delta_unit.encoded_delta,
                     (uut.package_sample_counter == 0) ? "[BYPASSED: RAW REF SAVED]" : "[SAVED TO RAM]"
            );
        end
    end

endmodule