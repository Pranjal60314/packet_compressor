`timescale 1ns / 1ps

module system_complete_tb;

    parameter SAMPLE_SIZE         = 16;
    parameter ADDR_WIDTH          = 10;
    parameter PACKAGE_SIZE        = 4;
    parameter FIFO_DEPTH_LOG2     = 11;
    parameter OUT_FIFO_DEPTH_LOG2 = 9;
    parameter SWAP_ENDIANNESS     = 1;
    parameter UART_MSB_FIRST      = 1;

    localparam FILE_PATH          = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin";
    localparam SAMPLES_PER_PACKET = 160;
    localparam TOTAL_SAMPLES      = 1000;
    localparam TOTAL_BYTES        = TOTAL_SAMPLES * 2; // 2000 raw 8-bit bytes
    localparam TOTAL_PACKETS      = TOTAL_SAMPLES / SAMPLES_PER_PACKET;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // -------------------------------------------------------------
    // Input FIFO Feeder Signals
    // -------------------------------------------------------------
    reg                         fifo_wr_en;
    reg  [SAMPLE_SIZE-1:0]      fifo_wr_data;
    wire                        fifo_full;
    wire                        fifo_almost_full;
    wire [FIFO_DEPTH_LOG2:0]    fifo_occupancy;

    reg                         enable_streaming;
    reg  [ADDR_WIDTH-1:0]       cfg_packet_sample_count;
    reg  [ADDR_WIDTH-1:0]       cfg_batch_size;
    reg  [ADDR_WIDTH-1:0]       cfg_package_size;
    wire                        packet_active;

    // Interconnect: Input Feeder -> top_level
    wire                        packet_start;
    wire [ADDR_WIDTH-1:0]       packet_sample_count;
    wire [ADDR_WIDTH-1:0]       batch_size;
    wire [ADDR_WIDTH-1:0]       package_size;
    wire [ADDR_WIDTH-1:0]       in_buf_addr;
    wire [SAMPLE_SIZE-1:0]      in_buf_data;
    wire                        pipeline_done;

    // Interconnect: top_level -> Output UART Bridge
    wire [31:0]                 compressed_data;
    wire                        compressed_we;

    // -------------------------------------------------------------
    // Output UART Bridge Signals
    // -------------------------------------------------------------
    wire                        out_fifo_full;
    wire                        out_fifo_almost_full;
    wire [OUT_FIFO_DEPTH_LOG2:0] out_fifo_occupancy;
    wire [7:0]                  uart_tx_data;
    wire                        uart_tx_valid;
    reg                         uart_tx_ready;

    // Testbench Variables & File Storage
    reg [7:0]                   raw_byte_buffer [0:TOTAL_BYTES-1];
    integer                     file_desc;
    integer                     byte_idx;
    integer                     words_captured;
    integer                     bytes_received_by_uart;

    // -------------------------------------------------------------
    // 1. DUT: Input FIFO Feeder (Exact Parameter & Port Match)
    // -------------------------------------------------------------
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

    // -------------------------------------------------------------
    // 2. DUT: Top-Level Compression Core
    // -------------------------------------------------------------
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

    // -------------------------------------------------------------
    // 3. DUT: Output 32-to-8-bit UART Bridge
    // -------------------------------------------------------------
    compressed_to_uart_bridge #(
        .FIFO_DEPTH_LOG2        (OUT_FIFO_DEPTH_LOG2),
        .MSB_FIRST              (UART_MSB_FIRST)
    ) u_uart_bridge (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .compressed_we          (compressed_we),
        .compressed_data        (compressed_data),
        .fifo_full              (out_fifo_full),
        .fifo_almost_full       (out_fifo_almost_full),
        .fifo_occupancy         (out_fifo_occupancy),

        .uart_tx_data           (uart_tx_data),
        .uart_tx_valid          (uart_tx_valid),
        .uart_tx_ready          (uart_tx_ready)
    );

    // -------------------------------------------------------------
    // 100 MHz Clock Generation
    // -------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------
    // 32-bit Word Logger
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (compressed_we) begin
            words_captured = words_captured + 1;
            $display("(Time: %0t ns) [COMPRESSOR OUT] 32-bit Word #%0d = 0x%08x", 
                     $time, words_captured, compressed_data);
        end
    end

    // -------------------------------------------------------------
    // Emulated External UART Receiver
    // -------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_ready          <= 1'b1;
            bytes_received_by_uart <= 0;
        end else begin
            if (uart_tx_valid && uart_tx_ready) begin
                bytes_received_by_uart <= bytes_received_by_uart + 1;
                $display("(Time: %0t ns) [UART TX -> PC] Byte #%0d = 0x%02x", 
                         $time, bytes_received_by_uart + 1, uart_tx_data);
                
                // Emulate UART baud delay (4 cycles)
                uart_tx_ready <= 1'b0;
                repeat (4) @(posedge clk);
                uart_tx_ready <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // VCD Waveform Dump
    // -------------------------------------------------------------
    initial begin
        $dumpfile("logs/tb_system_complete_dump.vcd");
        $dumpvars(0, system_complete_tb);
    end

    // -------------------------------------------------------------
    // Main Test Stimulus (Byte-by-Byte Assembly & Streaming)
    // -------------------------------------------------------------
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

        // Load 8-bit binary dataset
        file_desc = $fopen(FILE_PATH, "rb");
        if (file_desc != 0) begin
            $display("[INFO] Loading binary raw byte dataset from %s", FILE_PATH);
            $fread(raw_byte_buffer, file_desc);
            $fclose(file_desc);
        end else begin
            $display("[WARN] Could not find %s. Generating test byte pattern.", FILE_PATH);
            for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
                raw_byte_buffer[byte_idx] = byte_idx[7:0];
            end
        end

        // Apply Reset
        #40;
        rst_n = 1'b1;
        #20;

        @(posedge clk);
        enable_streaming = 1'b1;

        // Ingest 8-bit stream into the 16-bit FIFO (combines 2 bytes per sample)
        for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 2) begin
            @(posedge clk);
            
            while (fifo_full) begin
                fifo_wr_en = 1'b0;
                @(posedge clk);
            end

            fifo_wr_en   = 1'b1;
            // Big-endian assembly: byte 0 into [15:8], byte 1 into [7:0]
            fifo_wr_data = {raw_byte_buffer[byte_idx], raw_byte_buffer[byte_idx + 1]};
        end

        // End of stream
        @(posedge clk);
        fifo_wr_en   = 1'b0;
        fifo_wr_data = 16'h0000;

        // Wait for all packets to finish and UART drain
        wait (fifo_occupancy < SAMPLES_PER_PACKET && !packet_active);
        wait (out_fifo_occupancy == 0 && !uart_tx_valid);

        repeat (20) @(posedge clk);

        $display("\n========================================================");
        $display("END-TO-END SYSTEM TEST COMPLETE");
        $display("Packets Processed:              %0d", TOTAL_PACKETS);
        $display("Total 16-bit Samples Ingested:  %0d", TOTAL_SAMPLES);
        $display("Total 32-bit Words Compressed:  %0d", words_captured);
        $display("Total 8-bit Bytes Sent to PC:   %0d", bytes_received_by_uart);
        $display("Expected Bytes:                 %0d", words_captured * 4);
        $display("========================================================");

        $finish;
    end

endmodule