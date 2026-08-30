///////////////////////////////////////////////////////////////////////////////////////////////////
// Company: <Name>
//
// File: Packet_compressor_testbench.v
//
// Targeted device: <Family::PolarFireSoC> <Die::MPFS095T> <Package::FCSG325>
// Author: <Name>
//
/////////////////////////////////////////////////////////////////////////////////////////////////// 

`timescale 1ns/100ps

module Packet_compressor_testbench;

    // -------------------------------------------------------------------------
    // Parameters & Configuration
    // -------------------------------------------------------------------------
    // 115200 Baud = ~8680.55 ns per bit (BAUD_VAL = 13'h0036 at ~100 MHz)
    parameter BIT_PERIOD    = 8680; 
    parameter TOTAL_BYTES   = 2000;
    localparam FILE_PATH    = "/home/pythonofapollo/WorkSpace/Active/packet_compressor/build/telemetry_test/AMT00103_raw.bin";

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg  RX;
    wire TX;

    reg [7:0] raw_byte_buffer [0:TOTAL_BYTES-1];
    integer   file_desc;
    integer   byte_idx;
    integer   rx_captured_count;

    // -------------------------------------------------------------------------
    // Instantiate Unit Under Test (UUT): packet_compressor_sd
    // -------------------------------------------------------------------------
    packet_compressor_sd packet_compressor_sd_0 (
        .RX ( RX ),
        .TX ( TX )
    );

    // -------------------------------------------------------------------------
    // Task: Transmit 1 Byte to DUT over Serial UART RX
    // (1 Start bit [0], 8 Data bits [LSB-first], 1 Stop bit [1])
    // -------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data_byte);
        integer bit_idx;
        begin
            // Start bit (Active LOW)
            RX = 1'b0;
            #(BIT_PERIOD);

            // Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                RX = data_byte[bit_idx];
                #(BIT_PERIOD);
            end

            // Stop bit (Active HIGH)
            RX = 1'b1;
            #(BIT_PERIOD);

            // Inter-byte idle spacing
            #(BIT_PERIOD);
        end
    endtask

    // -------------------------------------------------------------------------
    // Serial Output Monitor: Captures Compressed Bytes Streamed on TX
    // -------------------------------------------------------------------------
    reg [7:0] captured_byte;
    integer   mon_bit_idx;

    always begin
        // Wait for Start bit falling edge on TX line
        @(negedge TX);

        // Sample at the midpoint of Start bit
        #(BIT_PERIOD / 2);

        if (TX == 1'b0) begin
            // Sample the 8 payload bits at the center of each bit period
            for (mon_bit_idx = 0; mon_bit_idx < 8; mon_bit_idx = mon_bit_idx + 1) begin
                #(BIT_PERIOD);
                captured_byte[mon_bit_idx] = TX;
            end

            // Sample Stop bit
            #(BIT_PERIOD);
            if (TX == 1'b1) begin
                rx_captured_count = rx_captured_count + 1;
                $display("[%0t ns] [COMPRESSED UART OUT] Byte #%0d = 0x%02X (%08b)", 
                         $time, rx_captured_count, captured_byte, captured_byte);
            end else begin
                $display("[%0t ns] [WARNING] Framing error detected on TX!", $time);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Waveform Dump Setup
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("logs/tb_packet_compressor_sd_dump.vcd");
        $dumpvars(0, Packet_compressor_testbench);
    end

    // -------------------------------------------------------------------------
    // Main Stimulus Procedure
    // -------------------------------------------------------------------------
    initial begin
        // Initialize UART line to IDLE (HIGH)
        RX                = 1'b1;
        rx_captured_count = 0;

        $display("===============================================================");
        $display("[%0t ns] Initializing packet_compressor_sd Testbench...", $time);
        $display("===============================================================");

        // Load binary dataset
        file_desc = $fopen(FILE_PATH, "rb");
        if (file_desc != 0) begin
            $display("[INFO] Successfully opened binary telemetry file: %s", FILE_PATH);
            $fread(raw_byte_buffer, file_desc);
            $fclose(file_desc);
        end else begin
            $display("[WARN] File not found at %s. Using synthetic fallback pattern.", FILE_PATH);
            for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
                raw_byte_buffer[byte_idx] = byte_idx[7:0];
            end
        end

        // Allow internal PolarFire Oscillator (PF_OSC) and CCC/PLL to lock and stabilize
        #50000;

        $display("---------------------------------------------------------------");
        $display("[%0t ns] Starting UART byte streaming into DUT RX...", $time);
        $display("---------------------------------------------------------------");

        // Stream binary telemetry dataset into the physical RX pin
        for (byte_idx = 0; byte_idx < TOTAL_BYTES; byte_idx = byte_idx + 1) begin
            send_uart_byte(raw_byte_buffer[byte_idx]);
        end

        // Wait for final packet processing and UART TX draining
        #(BIT_PERIOD * 500);

        $display("\n===============================================================");
        $display("SIMULATION COMPLETE");
        $display("Raw Telemetry Bytes Ingested: %0d", TOTAL_BYTES);
        $display("Compressed Bytes Captured:    %0d", rx_captured_count);
        if (TOTAL_BYTES > 0 && rx_captured_count > 0) begin
            $display("Compression Ratio Achieved:   %0.2f%%", 
                     (1.0 - (rx_captured_count * 1.0 / TOTAL_BYTES)) * 100.0);
        end
        $display("===============================================================");

        $finish;
    end

endmodule