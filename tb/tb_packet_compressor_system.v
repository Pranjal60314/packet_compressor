`timescale 1ns / 1ps

module packet_compressor_system_tb;

    parameter SAMPLE_SIZE         = 16;
    parameter ADDR_WIDTH          = 10;
    parameter PACKAGE_SIZE        = 4;
    parameter IN_FIFO_DEPTH_LOG2  = 11;
    parameter OUT_FIFO_DEPTH_LOG2 = 9;
    parameter SWAP_ENDIANNESS     = 1;
    parameter FIRST_BYTE_IS_MSB   = 1;
    parameter UART_MSB_FIRST      = 1;

    localparam FILE_PATH          = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin";
    localparam SAMPLES_PER_PACKET = 160; // Matches internal cfg_packet_sample_count = 8'hA0 (160)
    localparam TOTAL_SAMPLES      = 1000;
    localparam TOTAL_BYTES        = TOTAL_SAMPLES * 2; // 2000 bytes
    localparam TOTAL_PACKETS      = TOTAL_SAMPLES / SAMPLES_PER_PACKET;

    // Clock and Reset
    reg clk;
    reg rst_n;

    // 8-bit Ingestion Interface
    reg        in_fifo_wr_en;
    reg  [7:0] in_fifo_wr_data;
    wire       in_fifo_full;

    // Control
    reg        enable_streaming;

    // UART Output Interface
    wire [7:0] uart_tx_data;
    wire       uart_tx_valid;
    reg        uart_tx_ready;
    wire       out_fifo_full;

    // Testbench Variables & Buffers
    reg [7:0]  raw_byte_buffer [0:TOTAL_BYTES-1];
    integer    file_desc;
    integer    byte_idx;
    integer    bytes_received_by_uart;

    // -------------------------------------------------------------
    // DUT: Exact Port Match with packet_compressor_system
    // -------------------------------------------------------------
    packet_compressor_system #(
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .PACKAGE_SIZE           (PACKAGE_SIZE),
        .IN_FIFO_DEPTH_LOG2     (IN_FIFO_DEPTH_LOG2),
        .OUT_FIFO_DEPTH_LOG2    (OUT_FIFO_DEPTH_LOG2),
        .SWAP_ENDIANNESS        (SWAP_ENDIANNESS),
        .FIRST_BYTE_IS_MSB      (FIRST_BYTE_IS_MSB),
        .UART_MSB_FIRST         (UART_MSB_FIRST)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .in_fifo_wr_en    (in_fifo_wr_en),
        .in_fifo_wr_data  (in_fifo_wr_data),
        .in_fifo_full     (in_fifo_full),

        .enable_streaming (enable_streaming),

        .uart_tx_data     (uart_tx_data),
        .uart_tx_valid    (uart_tx_valid),
        .uart_tx_ready    (uart_tx_ready),
        .out_fifo_full    (out_fifo_full)
    );

    // -------------------------------------------------------------
    // 100 MHz Clock Generation
    // -------------------------------------------------------------
    always #5 clk = ~clk;

    // -------------------------------------------------------------
    // Emulate External UART Receiver (Consumes bytes from DUT)
    // -------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_ready          <= 1'b1;
            bytes_received_by_uart <= 0;
        end else begin
            if (uart_tx_valid && uart_tx_ready) begin
                bytes_received_by_uart <= bytes_received_by_uart + 1;
                $display("(Time: %0t ns) [UART OFFLOAD -> PC] Byte #%0d = 0x%02x", 
                         $time, bytes_received_by_uart + 1, uart_tx_data);
                
                // Emulate UART transmission delay (4 clock cycles busy)
                uart_tx_ready <= 1'b0;
                repeat (4) @(posedge clk);
                uart_tx_ready <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // Waveform Dump
    // -------------------------------------------------------------
    initial begin
        $dumpfile("logs/tb_packet_compressor_system_dump.vcd");
        $dumpvars(0, packet_compressor_system_tb);
    end

    // -------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------
    initial begin
        clk                    = 1'b0;
        rst_n                  = 1'b0;
        in_fifo_wr_en          = 1'b0;
        in_fifo_wr_data        = 8'h00;
        enable_streaming       = 1'b0;
        bytes_received_by_uart = 0;

        // Load Raw 8-Bit Binary Dataset
        file_desc = $fopen(FILE_PATH, "rb");
        if (file_desc != 0) begin
            $display("[INFO] Successfully opened dataset from %s", FILE_PATH);
            $fread(raw_byte_buffer, file_desc);
            $fclose(file_desc);
        end else begin
            $display("[WARN] File not found at %s. Using sequential test pattern.", FILE_PATH);
            for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
                raw_byte_buffer[byte_idx] = byte_idx[7:0];
            end
        end

        // Reset Sequence
        #40;
        rst_n = 1'b1;
        #20;

        // Enable automatic packet dispatching
        @(posedge clk);
        enable_streaming = 1'b1;

        // Feed data byte-by-byte into the 8-bit input port
        for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
            @(posedge clk);

            // Backpressure handling
            while (in_fifo_full) begin
                in_fifo_wr_en = 1'b0;
                @(posedge clk);
            end

            in_fifo_wr_en   = 1'b1;
            in_fifo_wr_data = raw_byte_buffer[byte_idx];
        end

        // Stop writing
        @(posedge clk);
        in_fifo_wr_en   = 1'b0;
        in_fifo_wr_data = 8'h00;

        // Wait until all complete packets are processed and UART finishes draining
        wait (dut.u_feeder.fifo_occupancy < SAMPLES_PER_PACKET && !dut.u_compression_core.pipeline_done == 0);
        wait (dut.u_uart_bridge.fifo_occupancy == 0 && !uart_tx_valid);

        repeat (50) @(posedge clk);

        $display("\n========================================================");
        $display("TESTBENCH COMPLETE");
        $display("Packets Expected:         %0d", TOTAL_PACKETS);
        $display("Raw Bytes Ingested:       %0d", TOTAL_BYTES);
        $display("Total Bytes Sent over TX: %0d", bytes_received_by_uart);
        $display("========================================================");

        $finish;
    end

endmodule