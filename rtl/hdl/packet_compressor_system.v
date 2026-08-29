`timescale 1ns / 1ps

module packet_compressor_system #(
    parameter SAMPLE_SIZE         = 16,
    parameter ADDR_WIDTH          = 10,
    parameter PACKAGE_SIZE        = 4,
    parameter IN_FIFO_DEPTH_LOG2  = 11,
    parameter OUT_FIFO_DEPTH_LOG2 = 9,
    parameter SWAP_ENDIANNESS     = 1,
    parameter FIRST_BYTE_IS_MSB   = 1,
    parameter UART_MSB_FIRST      = 1
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // -------------------------------------------------------------
    // External 8-Bit Ingestion Port
    // -------------------------------------------------------------
    input  wire                   in_fifo_wr_en,
    input  wire [7:0]             in_fifo_wr_data,
    output wire                   in_fifo_full,

    // -------------------------------------------------------------
    // Compression Configuration Control
    // -------------------------------------------------------------
    input  wire                   enable_streaming,

    // -------------------------------------------------------------
    // External UART Transmit Interface
    // -------------------------------------------------------------
    output wire [7:0]             uart_tx_data,
    output wire                   uart_tx_valid,
    input  wire                   uart_tx_ready,
    output wire                   out_fifo_full
);

    // Static Compression Configuration Constants
    localparam [ADDR_WIDTH-1:0] CFG_PACKET_SAMPLE_COUNT = 10'd160;
    localparam [ADDR_WIDTH-1:0] CFG_BATCH_SIZE          = 10'd16;
    localparam [ADDR_WIDTH-1:0] CFG_PACKAGE_SIZE        = 10'd4;

    // -------------------------------------------------------------
    // 8-bit to 16-bit Input Accumulator
    // -------------------------------------------------------------
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
                    byte_holding_reg <= in_fifo_wr_data;
                    byte_phase       <= 1'b1;
                end else begin
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
    // Internal Interconnect Wires
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

    fifo_stream_feeder #(
        .ADDR_WIDTH             (ADDR_WIDTH),
        .FIFO_DEPTH_LOG2        (IN_FIFO_DEPTH_LOG2),
        .SWAP_ENDIANNESS        (SWAP_ENDIANNESS)
    ) u_feeder (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .fifo_wr_en             (feeder_16bit_wr_en),
        .fifo_wr_data           (assembled_16bit_sample),
        .fifo_full              (in_fifo_full),
        .fifo_almost_full       (),
        .fifo_occupancy         (),

        .enable_streaming       (enable_streaming),
        .cfg_packet_sample_count(CFG_PACKET_SAMPLE_COUNT),
        .cfg_batch_size         (CFG_BATCH_SIZE),
        .cfg_package_size       (CFG_PACKAGE_SIZE),
        .packet_active          (),

        .packet_start           (packet_start),
        .packet_sample_count    (packet_sample_count),
        .batch_size             (batch_size),
        .package_size           (package_size),
        .in_buf_addr            (in_buf_addr),
        .in_buf_data            (in_buf_data),
        .pipeline_done          (pipeline_done)
    );

    // -------------------------------------------------------------
    // 2. Top-Level Compression Core
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
    // 3. Compressed Data to UART Bridge
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
        .fifo_almost_full       (),
        .fifo_occupancy         (),

        .uart_tx_data           (uart_tx_data),
        .uart_tx_valid          (uart_tx_valid),
        .uart_tx_ready          (uart_tx_ready)
    );

endmodule