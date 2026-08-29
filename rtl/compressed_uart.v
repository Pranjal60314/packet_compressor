`timescale 1ns / 1ps

module compressed_to_uart_bridge #(
    parameter FIFO_DEPTH_LOG2 = 9,
    parameter MSB_FIRST       = 1  
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        compressed_we,
    input  wire [31:0] compressed_data,
    output wire        fifo_full,
    output wire        fifo_almost_full,
    output reg  [FIFO_DEPTH_LOG2:0] fifo_occupancy,

    output reg  [7:0]  uart_tx_data,   // 8-bit byte output
    output reg         uart_tx_valid,  // Asserted when uart_tx_data is valid / ready to send
    input  wire        uart_tx_ready   // From UART: 1 when idle/ready to accept a new byte
);

    localparam FIFO_DEPTH = 1 << FIFO_DEPTH_LOG2;

    reg [31:0] mem [0:FIFO_DEPTH-1];
    reg [FIFO_DEPTH_LOG2-1:0] wr_ptr;
    reg [FIFO_DEPTH_LOG2-1:0] rd_ptr;

    assign fifo_full        = (fifo_occupancy == FIFO_DEPTH);
    assign fifo_almost_full = (fifo_occupancy >= (FIFO_DEPTH - 8));
    wire   fifo_empty       = (fifo_occupancy == 0);

    reg  fifo_pop;
    wire [31:0] fifo_dout = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr         <= {FIFO_DEPTH_LOG2{1'b0}};
            rd_ptr         <= {FIFO_DEPTH_LOG2{1'b0}};
            fifo_occupancy <= {(FIFO_DEPTH_LOG2+1){1'b0}};
        end else begin
            // Ingest 32-bit data from top_level
            if (compressed_we && !fifo_full) begin
                mem[wr_ptr] <= compressed_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Pop next word when current word's bytes are finished
            if (fifo_pop && !fifo_empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Track 32-bit word occupancy
            case ({compressed_we && !fifo_full, fifo_pop && !fifo_empty})
                2'b10: fifo_occupancy <= fifo_occupancy + 1'b1;
                2'b01: fifo_occupancy <= fifo_occupancy - 1'b1;
                default: ;
            endcase
        end
    end
    
    localparam STATE_IDLE      = 2'd0;
    localparam STATE_LOAD_WORD = 2'd1;
    localparam STATE_SEND_BYTE = 2'd2;
    localparam STATE_NEXT_BYTE = 2'd3;

    reg [1:0]  state;
    reg [31:0] holding_reg;
    reg [1:0]  byte_cnt;

    // Function to extract selected byte
    function [7:0] get_byte(input [31:0] word, input [1:0] idx);
        if (MSB_FIRST) begin
            case (idx)
                2'd0: get_byte = word[31:24];
                2'd1: get_byte = word[23:16];
                2'd2: get_byte = word[15:8];
                2'd3: get_byte = word[7:0];
            endcase
        end else begin
            case (idx)
                2'd0: get_byte = word[7:0];
                2'd1: get_byte = word[15:8];
                2'd2: get_byte = word[23:16];
                2'd3: get_byte = word[31:24];
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            fifo_pop      <= 1'b0;
            byte_cnt      <= 2'd0;
            holding_reg   <= 32'h0;
            uart_tx_data  <= 8'h0;
            uart_tx_valid <= 1'b0;
        end else begin
            fifo_pop <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    uart_tx_valid <= 1'b0;
                    if (!fifo_empty) begin
                        fifo_pop    <= 1'b1;
                        state       <= STATE_LOAD_WORD;
                    end
                end

                STATE_LOAD_WORD: begin
                    // Latch data popped from memory
                    holding_reg   <= fifo_dout;
                    byte_cnt      <= 2'd0;
                    uart_tx_data  <= get_byte(fifo_dout, 2'd0);
                    uart_tx_valid <= 1'b1;
                    state         <= STATE_SEND_BYTE;
                end

                STATE_SEND_BYTE: begin
                    // Wait for UART ready handshake
                    if (uart_tx_ready) begin
                        if (byte_cnt == 2'd3) begin
                            // All 4 bytes of 32-bit word transmitted
                            uart_tx_valid <= 1'b0;
                            state         <= STATE_IDLE;
                        end else begin
                            // Advance to next byte
                            uart_tx_valid <= 1'b0; // Drop valid for 1 cycle if UART expects pulse
                            byte_cnt      <= byte_cnt + 1'b1;
                            state         <= STATE_NEXT_BYTE;
                        end
                    end
                end

                STATE_NEXT_BYTE: begin
                    uart_tx_data  <= get_byte(holding_reg, byte_cnt);
                    uart_tx_valid <= 1'b1;
                    state         <= STATE_SEND_BYTE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule