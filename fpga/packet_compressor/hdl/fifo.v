`timescale 1ns / 1ps

module fwft_fifo #(
    parameter DEPTH = 512,
    parameter WIDTH = 16
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // Write Interface
    input  wire                   wr_en,
    input  wire [WIDTH-1:0]       din,
    output wire                   full,

    // Read Interface (First-Word Fall-Through)
    input  wire                   rd_en,
    output wire [WIDTH-1:0]       dout,
    output wire                   valid,
    output reg  [$clog2(DEPTH):0] count
);

    localparam ADDR_WIDTH = $clog2(DEPTH);

    reg [WIDTH-1:0]    mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    
    wire empty = (wr_ptr == rd_ptr);
    assign valid = !empty;

    // Asynchronous read head
    assign dout = mem[rd_ptr[ADDR_WIDTH-1:0]];

    wire can_write = wr_en && (!full || rd_en);
    wire can_read  = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
            count  <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (can_write) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (can_read) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({can_write, can_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule