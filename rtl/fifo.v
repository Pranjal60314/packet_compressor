`timescale 1ns / 1ps
module fifo #(
        parameter DEPTH = 32,
        parameter WIDTH = 8
    )(
        input wire clk,
        input wire rst,

        input wire wr_en,
        input wire rd_en,
        input wire [WIDTH-1:0] din,

        output reg [WIDTH-1:0] dout,
        output wire full,
        output wire empty
    );
        reg [WIDTH-1:0] mem [0:DEPTH-1];
        reg [$clog2(DEPTH):0] wr_ptr, rd_ptr;

        assign empty = (wr_ptr == rd_ptr);
        assign full  = (wr_ptr - rd_ptr == DEPTH);

        always @(posedge clk) begin
            if (rst) begin
                wr_ptr <= 0;
                rd_ptr <= 0;
            end else begin
                // write
                if (wr_en && !full) begin
                    mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
                    wr_ptr <= wr_ptr + 1;
                end

                // read
                if (rd_en && !empty) begin
                    dout <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
                    rd_ptr <= rd_ptr + 1;
                end
            end
        end

    endmodule
