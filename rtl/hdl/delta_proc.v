`timescale 1ns / 1ps

module delta_processing (
    input  wire [15:0] previous_x,                                    
    input  wire [15:0] current_x,                                    
    output wire [15:0] encoded_delta                               
);
                                                    
    wire signed [16:0] prev_ext;
    wire signed [16:0] curr_ext;
    
    assign prev_ext = {1'b0, previous_x};
    assign curr_ext = {1'b0, current_x};
                                                         
    wire signed [16:0] delta_signed;
    assign delta_signed = curr_ext - prev_ext;

                                                                    
    wire signed [16:0] neg_delta_signed;
    assign neg_delta_signed = -delta_signed;
                               
    wire [15:0] pos_result;
    wire [15:0] neg_result;
                                          
    assign pos_result = delta_signed[14:0] << 1;             //assuming the delat is positive we use 2*|delta|                             
    assign neg_result = (neg_delta_signed[14:0] << 1) - 16'd1;//assuming the delta is negative we use 2*|delta| - 1 where the mod delta is something we process previously in line 20 
    assign encoded_delta = (delta_signed[16] == 1'b0) ? pos_result : neg_result;

endmodule