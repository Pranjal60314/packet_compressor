`timescale 1ns / 1ps

module fifo_stream_feeder #(
    parameter ADDR_WIDTH        = 10,
    parameter FIFO_DEPTH_LOG2   = 11,   // Depth = 2048 16-bit words (holds multiple packets)
    parameter SWAP_ENDIANNESS   = 1,    // 1: Swap bytes {7:0, 15:8}, 0: Direct
    parameter FIRST_BYTE_IS_MSB = 1     // 1: 1st byte -> [15:8], 2nd byte -> [7:0] (Big Endian Ingestion)
                                        // 0: 1st byte -> [7:0], 2nd byte -> [15:8] (Little Endian Ingestion)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // -------------------------------------------------------------
    // Upstream 8-bit Ingestion Interface
    // -------------------------------------------------------------
    input  wire                         fifo_wr_en,
    input  wire [7:0]                   fifo_wr_data,
    output wire                         fifo_full,
    output wire                         fifo_almost_full,
    output reg  [FIFO_DEPTH_LOG2:0]     fifo_occupancy,

    // -------------------------------------------------------------
    // Control & Configuration Interface
    // -------------------------------------------------------------
    input  wire                         enable_streaming,
    input  wire [ADDR_WIDTH-1:0]        cfg_packet_sample_count,
    input  wire [ADDR_WIDTH-1:0]        cfg_batch_size,
    input  wire [ADDR_WIDTH-1:0]        cfg_package_size,
    output reg                          packet_active,

    // -------------------------------------------------------------
    // Interface to top_level (UUT)
    // -------------------------------------------------------------
    output reg                          packet_start,
    output reg  [ADDR_WIDTH-1:0]        packet_sample_count,
    output reg  [ADDR_WIDTH-1:0]        batch_size,
    output reg  [ADDR_WIDTH-1:0]        package_size,
    input  wire [ADDR_WIDTH-1:0]        in_buf_addr,
    output wire [15:0]                  in_buf_data,
    input  wire                         pipeline_done
);

    localparam FIFO_DEPTH = 1 << FIFO_DEPTH_LOG2;

    // 16-bit Dual-Port RAM storage for the Circular FIFO
    reg [15:0] mem [0:FIFO_DEPTH-1];

    reg [FIFO_DEPTH_LOG2-1:0] wr_ptr;
    reg [FIFO_DEPTH_LOG2-1:0] rd_ptr;

    // 8-bit to 16-bit Accumulator Registers
    reg [7:0]  byte_holding_reg;
    reg        byte_phase; // 0: Expecting 1st byte, 1: Expecting 2nd byte

    // FSM States
    localparam STATE_IDLE        = 2'd0;
    localparam STATE_START_PULSE = 2'd1;
    localparam STATE_WAIT_BUSY   = 2'd2;
    localparam STATE_WAIT_DONE   = 2'd3;

    reg [1:0] state;

    // FIFO Status Flags (Based on 16-bit word occupancy)
    assign fifo_full        = (fifo_occupancy == FIFO_DEPTH);
    assign fifo_almost_full = (fifo_occupancy >= (FIFO_DEPTH - 16));

    // -------------------------------------------------------------
    // 8-bit to 16-bit Assembly & FIFO Memory Push
    // -------------------------------------------------------------
    wire push_word = fifo_wr_en && (byte_phase == 1'b1) && !fifo_full;
    wire [15:0] assembled_16bit_word = (FIRST_BYTE_IS_MSB) ? 
                                       {byte_holding_reg, fifo_wr_data} : 
                                       {fifo_wr_data, byte_holding_reg};

    wire commit_packet_read = (state == STATE_WAIT_DONE) && (pipeline_done == 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr              <= {FIFO_DEPTH_LOG2{1'b0}};
            rd_ptr              <= {FIFO_DEPTH_LOG2{1'b0}};
            fifo_occupancy      <= {(FIFO_DEPTH_LOG2+1){1'b0}};
            byte_phase          <= 1'b0;
            byte_holding_reg    <= 8'h00;
        end else begin
            // 8-bit Ingestion / Accumulation Logic
            if (fifo_wr_en && !fifo_full) begin
                if (byte_phase == 1'b0) begin
                    byte_holding_reg <= fifo_wr_data;
                    byte_phase       <= 1'b1;
                end else begin
                    mem[wr_ptr]      <= assembled_16bit_word;
                    wr_ptr           <= wr_ptr + 1'b1;
                    byte_phase       <= 1'b0;
                end
            end

            // Read Pointer Retirement (Advance on packet completion)
            if (commit_packet_read) begin
                rd_ptr <= rd_ptr + cfg_packet_sample_count;
            end

            // Occupancy Tracking (tracks 16-bit words available)
            case ({push_word, commit_packet_read})
                2'b10: fifo_occupancy <= fifo_occupancy + 1'b1;
                2'b01: fifo_occupancy <= fifo_occupancy - cfg_packet_sample_count;
                2'b11: fifo_occupancy <= fifo_occupancy + 1'b1 - cfg_packet_sample_count;
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------
    // Random-Access Read Window relative to FIFO rd_ptr
    // -------------------------------------------------------------
    wire [FIFO_DEPTH_LOG2-1:0] actual_read_addr;
    assign actual_read_addr = rd_ptr + in_buf_addr;

    wire [15:0] raw_read_data;
    assign raw_read_data = mem[actual_read_addr];

    assign in_buf_data = (SWAP_ENDIANNESS) ? 
                         {raw_read_data[7:0], raw_read_data[15:8]} : 
                         raw_read_data;

    // -------------------------------------------------------------
    // Packet Dispatch FSM
    // -------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= STATE_IDLE;
            packet_start        <= 1'b0;
            packet_active       <= 1'b0;
            packet_sample_count <= {ADDR_WIDTH{1'b0}};
            batch_size          <= {ADDR_WIDTH{1'b0}};
            package_size        <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (state)
                STATE_IDLE: begin
                    packet_start <= 1'b0;
                    // Fire when FIFO contains at least one complete packet of 16-bit samples
                    if (enable_streaming && (fifo_occupancy >= cfg_packet_sample_count)) begin
                        packet_sample_count <= cfg_packet_sample_count;
                        batch_size          <= cfg_batch_size;
                        package_size        <= cfg_package_size;
                        packet_start        <= 1'b1;
                        packet_active       <= 1'b1;
                        state               <= STATE_START_PULSE;
                    end
                end

                STATE_START_PULSE: begin
                    packet_start <= 1'b0;
                    state        <= STATE_WAIT_BUSY;
                end

                STATE_WAIT_BUSY: begin
                    if (pipeline_done == 1'b0) begin
                        state <= STATE_WAIT_DONE;
                    end
                end

                STATE_WAIT_DONE: begin
                    if (pipeline_done == 1'b1) begin
                        packet_active <= 1'b0;
                        state         <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule