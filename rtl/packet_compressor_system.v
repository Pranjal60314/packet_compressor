`timescale 1ns / 1ps

module packet_compressor_system #(
    parameter SAMPLE_SIZE         = 16,
    parameter ADDR_WIDTH          = 10,
    parameter PACKAGE_SIZE        = 4,
    parameter IN_FIFO_DEPTH_LOG2  = 11,
    parameter OUT_FIFO_DEPTH_LOG2 = 9,
    parameter SWAP_ENDIANNESS     = 1,
    parameter FIRST_BYTE_IS_MSB   = 1,    // 1: Big-Endian {byte0, byte1}, 0: Little-Endian {byte1, byte0}
    parameter UART_MSB_FIRST      = 1
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // -------------------------------------------------------------
    // External 8-Bit Ingestion Port (Connect directly to UART RX / SPI)
    // -------------------------------------------------------------
    input  wire                         in_fifo_wr_en,
    input  wire [7:0]                   in_fifo_wr_data,  // Pure 8-bit input
    output wire                         in_fifo_full,
    // output wire                         in_fifo_almost_full,

    // -------------------------------------------------------------
    // Compression Configuration
    // -------------------------------------------------------------
     input  wire                         enable_streaming,
    // output wire                         packet_active,

    // -------------------------------------------------------------
    // External UART Transmit Interface (Connect to COREUART TX)
    // -------------------------------------------------------------
    output wire [7:0]                   uart_tx_data,
    output wire                         uart_tx_valid,
    input  wire                         uart_tx_ready,
    output wire                         out_fifo_full
    // output wire                         out_fifo_almost_full
);

    // -------------------------------------------------------------
    // 8-bit to 16-bit Accumulator
    // -------------------------------------------------------------
    reg [ADDR_WIDTH-1:0]        cfg_packet_sample_count = 8'hA0;
    reg [ADDR_WIDTH-1:0]        cfg_batch_size = 8'h10;
    reg [ADDR_WIDTH-1:0]        cfg_package_size = 8'h4;

    reg  [7:0]             byte_holding_reg;
    reg                    byte_phase;
    reg  [SAMPLE_SIZE-1:0] assembled_16bit_sample;
    reg                    feeder_16bit_wr_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_phase             <= 1'b0;
            byte_holding_reg       <= 8'h00;
            assembled_16bit_sample <= {SAMPLE_SIZE{1'b0}};
            feeder_16bit_wr_en     <= 1'b0;
        end else begin
            feeder_16bit_wr_en <= 1'b0;

            if (in_fifo_wr_en && !in_fifo_full) begin
                if (byte_phase == 1'b0) begin
                    // Store the 1st byte
                    byte_holding_reg <= in_fifo_wr_data;
                    byte_phase       <= 1'b1;
                end else begin
                    // 2nd byte arrived: assemble 16-bit word and push to feeder FIFO
                    assembled_16bit_sample <= (FIRST_BYTE_IS_MSB) ? 
                                              {byte_holding_reg, in_fifo_wr_data} : 
                                              {in_fifo_wr_data, byte_holding_reg};
                    feeder_16bit_wr_en     <= 1'b1;
                    byte_phase             <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------
    // Internal Interconnects
    // -------------------------------------------------------------
    wire                    packet_start;
    wire [ADDR_WIDTH-1:0]   packet_sample_count;
    wire [ADDR_WIDTH-1:0]   batch_size;
    wire [ADDR_WIDTH-1:0]   package_size;
    wire [ADDR_WIDTH-1:0]   in_buf_addr;
    wire [SAMPLE_SIZE-1:0]  in_buf_data;
    wire                    pipeline_done;

    wire [31:0]             compressed_data;
    wire                    compressed_we;

    // -------------------------------------------------------------
    // 1. Input FIFO Stream Feeder (16-bit storage)
    // -------------------------------------------------------------
    fifo_stream_feeder #(
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .ADDR_WIDTH             (ADDR_WIDTH),
        .FIFO_DEPTH_LOG2        (IN_FIFO_DEPTH_LOG2),
        .SWAP_ENDIANNESS        (SWAP_ENDIANNESS)
    ) u_feeder (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .fifo_wr_en             (feeder_16bit_wr_en),
        .fifo_wr_data           (assembled_16bit_sample),
        .fifo_full              (in_fifo_full),
        .fifo_almost_full       (),//(in_fifo_almost_full),
        .fifo_occupancy         (),

        .enable_streaming       (enable_streaming),
        .cfg_packet_sample_count(cfg_packet_sample_count),
        .cfg_batch_size         (cfg_batch_size),
        .cfg_package_size       (cfg_package_size),
        .packet_active          (),//(packet_active),

        .packet_start           (packet_start),
        .packet_sample_count    (packet_sample_count),
        .batch_size             (batch_size),
        .package_size           (package_size),
        .in_buf_addr            (in_buf_addr),
        .in_buf_data            (in_buf_data),
        .pipeline_done          (pipeline_done)
    );

    // -------------------------------------------------------------
    // 2. Compression Top-Level
    // -------------------------------------------------------------
    top_level #(
        .ADDR_WIDTH             (ADDR_WIDTH),
        .SAMPLE_SIZE            (SAMPLE_SIZE),
        .PACKAGE_SIZE           (PACKAGE_SIZE)
    ) u_compression_core (
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
    // 3. UART Bridge
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
        .fifo_occupancy         (),

        .uart_tx_data           (uart_tx_data),
        .uart_tx_valid          (uart_tx_valid),
        .uart_tx_ready          (uart_tx_ready)
    );

endmodule