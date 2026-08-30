`timescale 1ns / 1ps

module tb_packet_compressor_pipeline();

    // -------------------------------------------------------------------------
    // System & UART Timing Parameters
    // -------------------------------------------------------------------------
    localparam CLK_HZ          = 50_000_000;               // 50 MHz Fabric Clock
    localparam CLK_PERIOD      = 20;                       // 20 ns
    localparam BIT_RATE        = 115200;                   // Baud rate
    localparam BIT_PERIOD_NS   = 1_000_000_000 / BIT_RATE; // ~8680 ns per serial bit

    // -------------------------------------------------------------------------
    // Compression Architecture Parameters
    // -------------------------------------------------------------------------
    localparam SAMPLE_SIZE     = 16;
    localparam ADDR_WIDTH      = 10;
    localparam PACKAGE_SIZE    = 4;

    // -------------------------------------------------------------------------
    // Dataset Parameters
    // -------------------------------------------------------------------------
    localparam FILE_PATH          = "./build/telemetry_test/AMT00103_raw.bin";
    localparam SAMPLES_PER_PACKET = 160;                   // cfg_packet_sample_count
    localparam TOTAL_SAMPLES      = 1000;
    localparam TOTAL_BYTES        = TOTAL_SAMPLES * 2;     // 2000 bytes (16-bit words)
    localparam TOTAL_PACKETS      = TOTAL_SAMPLES / SAMPLES_PER_PACKET;

    // -------------------------------------------------------------------------
    // Driving Signals & Buffers
    // -------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        tb_uart_rxd;
    wire       tb_uart_txd;

    reg [7:0]  raw_byte_buffer [0:TOTAL_BYTES-1];
    integer    file_desc;
    integer    byte_idx;
    integer    compressed_bytes_out;

    // -------------------------------------------------------------------------
    // 1. Clock Generation (50 MHz)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // 2. buffered_uart_rx -> packet_compressor_system Handshake
    // -------------------------------------------------------------------------
    wire [7:0] rx_fifo_dout;
    wire       rx_fifo_empty;
    wire       rx_fifo_full;
    wire       rx_break;
    wire       comp_in_fifo_full;

    // Transfer byte as soon as RX FIFO has data and compressor has room
    wire       rx_to_comp_wr_en   = !rx_fifo_empty && !comp_in_fifo_full;
    wire [7:0] rx_to_comp_wr_data = rx_fifo_dout;

    buffered_uart_rx #(
        .BIT_RATE       (BIT_RATE),
        .CLK_HZ         (CLK_HZ),
        .FIFO_DEPTH     (512)
    ) u_buffered_uart_rx (
        .clk            (clk),
        .resetn         (rst_n),
        .uart_rxd       (tb_uart_rxd),
        .uart_rx_en     (1'b1),
        .rd_data        (rx_fifo_dout),
        .rd_en          (rx_to_comp_wr_en),
        .fifo_empty     (rx_fifo_empty),
        .fifo_full      (rx_fifo_full),
        .rx_break       (rx_break)
    );

    // -------------------------------------------------------------------------
    // 3. packet_compressor_system Core
    // -------------------------------------------------------------------------
    wire [7:0] comp_tx_data;
    wire       comp_tx_valid;
    wire       comp_out_fifo_full;
    wire       tx_fifo_full;

    wire       comp_tx_ready = !tx_fifo_full;

    packet_compressor_system #(
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .PACKAGE_SIZE           (PACKAGE_SIZE),
        .IN_FIFO_DEPTH_LOG2     (11),
        .OUT_FIFO_DEPTH_LOG2    (9),
        .SWAP_ENDIANNESS        (1),
        .FIRST_BYTE_IS_MSB      (1),
        .UART_MSB_FIRST         (1)
    ) u_compressor_system (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .in_fifo_wr_en          (rx_to_comp_wr_en),
        .in_fifo_wr_data        (rx_to_comp_wr_data),
        .in_fifo_full           (comp_in_fifo_full),
        .enable_streaming       (1'b1),
        .uart_tx_data           (comp_tx_data),
        .uart_tx_valid          (comp_tx_valid),
        .uart_tx_ready          (comp_tx_ready),
        .out_fifo_full          (comp_out_fifo_full)
    );

    // -------------------------------------------------------------------------
    // 4. packet_compressor_system -> buffered_uart_tx Bridge
    // -------------------------------------------------------------------------
    wire tx_busy;

    buffered_uart_tx #(
        .BIT_RATE       (BIT_RATE),
        .CLK_HZ         (CLK_HZ),
        .FIFO_DEPTH     (256)
    ) u_buffered_uart_tx (
        .clk            (clk),
        .resetn         (rst_n),
        .tx_en          (1'b1),
        .wr_data        (comp_tx_data),
        .wr_en          (comp_tx_valid && comp_tx_ready),
        .fifo_full      (tx_fifo_full),
        .uart_txd       (tb_uart_txd),
        .tx_busy        (tx_busy)
    );

    // -------------------------------------------------------------------------
    // Tasks: Serial Data Driver
    // -------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data_byte);
        integer i;
        begin
            // Start bit (LOW)
            tb_uart_rxd = 1'b0;
            #(BIT_PERIOD_NS);

            // 8 Data bits (LSB First)
            for (i = 0; i < 8; i = i + 1) begin
                tb_uart_rxd = data_byte[i];
                #(BIT_PERIOD_NS);
            end

            // Stop bit (HIGH)
            tb_uart_rxd = 1'b1;
            #(BIT_PERIOD_NS);

            // Inter-byte gap
            #(BIT_PERIOD_NS);
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor: Serial Receiver Capturing TX Line
    // -------------------------------------------------------------------------
    reg [7:0] captured_byte;
    integer bit_idx;
    
    always begin
        @(negedge tb_uart_txd);
        #(BIT_PERIOD_NS / 2); // Sample at midpoint of start bit

        if (tb_uart_txd == 1'b0) begin
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(BIT_PERIOD_NS);
                captured_byte[bit_idx] = tb_uart_txd;
            end

            #(BIT_PERIOD_NS); // Stop bit
            if (tb_uart_txd == 1'b1) begin
                compressed_bytes_out = compressed_bytes_out + 1;
                $display("[%0t ns] [UART TX OUT] Byte #%0d = 0x%02X (%08b)", 
                         $time, compressed_bytes_out, captured_byte, captured_byte);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Waveform Dump Setup
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("logs/tb_packet_compressor_pipeline.vcd");
        $dumpvars(0, tb_packet_compressor_pipeline);
    end

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        tb_uart_rxd          = 1'b1; // Idle line is HIGH
        rst_n                = 1'b0;
        compressed_bytes_out = 0;

        // Load Binary Telemetry Dataset
        file_desc = $fopen(FILE_PATH, "rb");
        if (file_desc != 0) begin
            $display("[INFO] Successfully opened binary telemetry file: %s", FILE_PATH);
            $fread(raw_byte_buffer, file_desc);
            $fclose(file_desc);
        end else begin
            $display("[WARN] File not found at %s! Using synthetic incremental fallback pattern.", FILE_PATH);
            for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
                raw_byte_buffer[byte_idx] = byte_idx[7:0];
            end
        end

        // Apply Reset
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        $display("----------------------------------------------------------------");
        $display("[%0t ns] Starting UART Telemetry Streaming...", $time);
        $display("----------------------------------------------------------------");

        // Send binary dataset byte-by-byte through external UART RX
        for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
            // Wait if RX buffer is getting full before pushing next serial frame
            while (rx_fifo_full) begin
                #(BIT_PERIOD_NS);
            end
            send_uart_byte(raw_byte_buffer[byte_idx]);
        end

        // Wait until all data clears the RX buffer, processing pipeline, and TX buffer
        wait (!tx_busy && rx_fifo_empty);
        #(BIT_PERIOD_NS * 50);

        $display("\n========================================================");
        $display("END-TO-END SIMULATION COMPLETE");
        $display("Expected Packets:         %0d", TOTAL_PACKETS);
        $display("Raw Telemetry Ingested:   %0d bytes (%0d samples)", TOTAL_BYTES, TOTAL_SAMPLES);
        $display("Compressed UART Transmit: %0d bytes", compressed_bytes_out);
        if (TOTAL_BYTES > 0) begin
            $display("Achieved Compression:     %0.2f%%", 
                     (1.0 - (compressed_bytes_out * 1.0 / TOTAL_BYTES)) * 100.0);
        end
        $display("========================================================");

        $finish;
    end

endmodule