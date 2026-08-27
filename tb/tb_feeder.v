`timescale 1ns / 1ps

module fifo_stream_feeder_tb;

    parameter SAMPLE_SIZE       = 16;
    parameter ADDR_WIDTH        = 10;
    parameter PACKAGE_SIZE      = 4;
    parameter FIFO_DEPTH_LOG2   = 11;
    parameter SWAP_ENDIANNESS   = 1;

    localparam FILE_PATH          = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin";
    localparam SAMPLES_PER_PACKET = 160;
    localparam TOTAL_SAMPLES      = 1000;
    localparam TOTAL_PACKETS      = TOTAL_SAMPLES / SAMPLES_PER_PACKET;

    reg clk;
    reg rst_n;

    reg                     fifo_wr_en;
    reg  [SAMPLE_SIZE-1:0]  fifo_wr_data;
    wire                    fifo_full;
    wire                    fifo_almost_full;
    wire [FIFO_DEPTH_LOG2:0] fifo_occupancy;

    reg                     enable_streaming;
    reg  [ADDR_WIDTH-1:0]   cfg_packet_sample_count;
    reg  [ADDR_WIDTH-1:0]   cfg_batch_size;
    reg  [ADDR_WIDTH-1:0]   cfg_package_size;
    wire                    packet_active;

    wire                    packet_start;
    wire [ADDR_WIDTH-1:0]   packet_sample_count;
    wire [ADDR_WIDTH-1:0]   batch_size;
    wire [ADDR_WIDTH-1:0]   package_size;
    wire [ADDR_WIDTH-1:0]   in_buf_addr;
    wire [SAMPLE_SIZE-1:0]  in_buf_data;
    wire                    pipeline_done;

    wire [31:0]             compressed_data;
    wire                    compressed_we;

    reg [SAMPLE_SIZE-1:0]   mock_file_buffer [0:TOTAL_SAMPLES-1];
    integer                 file_desc;
    integer                 wr_idx;
    integer                 words_captured;

    fifo_stream_feeder #(
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .FIFO_DEPTH_LOG2        (FIFO_DEPTH_LOG2),
        .SWAP_ENDIANNESS        (SWAP_ENDIANNESS)
    ) u_feeder (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .fifo_wr_en             (fifo_wr_en),
        .fifo_wr_data           (fifo_wr_data),
        .fifo_full              (fifo_full),
        .fifo_almost_full       (fifo_almost_full),
        .fifo_occupancy         (fifo_occupancy),

        .enable_streaming       (enable_streaming),
        .cfg_packet_sample_count(cfg_packet_sample_count),
        .cfg_batch_size         (cfg_batch_size),
        .cfg_package_size       (cfg_package_size),
        .packet_active          (packet_active),

        .packet_start           (packet_start),
        .packet_sample_count    (packet_sample_count),
        .batch_size             (batch_size),
        .package_size           (package_size),
        .in_buf_addr            (in_buf_addr),
        .in_buf_data            (in_buf_data),
        .pipeline_done          (pipeline_done)
    );

    top_level #(
        .ADDR_WIDTH             (ADDR_WIDTH),
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .PACKAGE_SIZE           (PACKAGE_SIZE)
    ) u_top_level (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .packet_start           (packet_start),
        .packet_sample_count    (packet_sample_count),
        .batch_size             (batch_size),
        .package_size           (package_size),
        .in_buf_addr            (in_buf_addr),
        .in_buf_data            (in_buf_data),
        .compressed_data        (compressed_data),
        .compressed_we          (compressed_we),
        .pipeline_done          (pipeline_done)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (compressed_we) begin
            words_captured = words_captured + 1;
            $display("(Time: %0t ns) [OUT] 32-bit Word #%0d = 0x%08x", 
                     $time, words_captured, compressed_data);
        end
    end

    initial begin
        $dumpfile("logs/tb_fifo_feeder_dump.vcd");
        $dumpvars(0, fifo_stream_feeder_tb);
    end

    initial begin
        clk                     = 1'b0;
        rst_n                   = 1'b0;
        fifo_wr_en              = 1'b0;
        fifo_wr_data            = 16'h0000;
        enable_streaming        = 1'b0;
        cfg_packet_sample_count = SAMPLES_PER_PACKET;
        cfg_batch_size          = 10'd16;
        cfg_package_size        = 10'd4;
        words_captured          = 0;

        file_desc = $fopen(FILE_PATH, "rb");

        if (file_desc != 0) begin
            $display("[INFO] Loading binary dataset from %s", FILE_PATH);
            $fread(mock_file_buffer, file_desc);
            $fclose(file_desc);

        end else begin
            $display("[WARN] Could not find %s. Using sequential test data pattern.", FILE_PATH);
            for (wr_idx = 0; wr_idx < TOTAL_SAMPLES; wr_idx = wr_idx + 1) begin
                mock_file_buffer[wr_idx] = wr_idx[15:0];
            end
        end

        #40;
        rst_n = 1'b1;
        #20;

        @(posedge clk);
        enable_streaming = 1'b1;

        for (wr_idx = 0; wr_idx < TOTAL_SAMPLES; wr_idx = wr_idx + 1) begin
            @(posedge clk);
            
            while (fifo_full) begin
                fifo_wr_en = 1'b0;
                @(posedge clk);
            end

            fifo_wr_en   = 1'b1;
            fifo_wr_data = mock_file_buffer[wr_idx];
        end

        @(posedge clk);
        fifo_wr_en   = 1'b0;
        fifo_wr_data = 16'h0000;

        wait (fifo_occupancy < SAMPLES_PER_PACKET && !packet_active);

        repeat (20) @(posedge clk);

        $display("\n========================================================");
        $display("SIMULATION COMPLETE");
        $display("Total Packets Triggered: %0d", TOTAL_PACKETS);
        $display("Total Compressed Words Output: %0d", words_captured);
        $display("Remaining FIFO Occupancy: %0d samples", fifo_occupancy);
        $display("========================================================");

        $finish;
    end

endmodule