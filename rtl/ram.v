module ram #(
    parameter DATA_WIDTH = 16,                                    
    parameter ADDR_WIDTH = 10                                                   
)(
    input  wire                  clk,                  
    input  wire                  we,                                         
    input  wire [ADDR_WIDTH-1:0] addr,                  
    input  wire [DATA_WIDTH-1:0] din,                           
    output reg  [DATA_WIDTH-1:0] dout                             
);
             
    localparam DEPTH = 1 << ADDR_WIDTH;
    
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;                                  
        end
                                         
        dout <= mem[addr]; 
    end

endmodule