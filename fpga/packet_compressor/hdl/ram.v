module ram #(
    parameter SAMPLE_SIZE = 16,                                    
    parameter ADDR_WIDTH = 10                                                   
)(
    input  wire                  clk,                  
    input  wire                  we,                                         
    input  wire [ADDR_WIDTH-1:0] addr,                  
    input  wire [SAMPLE_SIZE-1:0] din,                           
    output reg  [SAMPLE_SIZE-1:0] dout                             
);
             
    localparam DEPTH = 1 << ADDR_WIDTH;
    
    reg [SAMPLE_SIZE-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;                                  
        end
                                         
        dout <= mem[addr]; 
    end

endmodule