`timescale 1ns / 1ps

module k_estimation #(
    parameter SAMPLE_SIZE = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,

    input  wire [3:0]  block_size,   
    input  wire [3:0]  start_addr,   

    output reg         done,

    output reg  [7:0]  optimal_k,
    output reg  [31:0] min_length,   
    output reg  [3:0]  mem_addr,   
      
    input  wire [15:0] mem_data
);

    localparam IDLE     = 2'b00,
               FETCH    = 2'b01,
               ACCUM    = 2'b10,
               COMPARE  = 2'b11;

    reg [1:0]  state;
    reg [3:0]  index_counter;
    reg [31:0] comp_len [0:SAMPLE_SIZE-1];

    wire [31:0] step_cost [0:SAMPLE_SIZE-1];
    genvar j;
    generate
        for (j = 0; j < SAMPLE_SIZE; j = j + 1) begin : gen_k_costs
            assign step_cost[j] = (mem_data >> j) + 1'b1 + j;
        end
    endgenerate

    integer k;
    reg [31:0] current_min;
    reg [7:0]  current_k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            index_counter <= 4'd0;
            mem_addr      <= 4'd0;
            done          <= 1'b0;
            optimal_k     <= 8'd0;
            min_length    <= 32'd0;
            for (k = 0; k < SAMPLE_SIZE; k = k + 1) comp_len[k] <= 32'd0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        index_counter <= 4'd0;
                        mem_addr      <= 4'd0; // Issue request for sample 0
                        for (k = 0; k < SAMPLE_SIZE; k = k + 1) comp_len[k] <= 32'd0;
                        state         <= FETCH;
                    end
                end

                FETCH: begin
                    // RAM latches addr 0. Issue prefetch for sample 1
                    mem_addr <= 4'd1;
                    state    <= ACCUM;
                end

                ACCUM: begin
                    // mem_data now contains valid data for index_counter
                    for (k = 0; k < SAMPLE_SIZE; k = k + 1) begin
                        comp_len[k] <= comp_len[k] + step_cost[k];
                    end

                    //$display("[K_ESTIMATOR] Memory Data: %h Index: %d", mem_data, index_counter);

                    if (index_counter >= block_size - 1'b1) begin
                        state <= COMPARE;
                    end else begin
                        index_counter <= index_counter + 1'b1;
                        mem_addr      <= mem_addr + 1'b1; // Issue prefetch for next sample
                        state         <= ACCUM;
                    end
                end

                COMPARE: begin
                    current_min = comp_len[0];
                    current_k   = 8'd0;
                    
                    for (k = 1; k < SAMPLE_SIZE; k = k + 1) begin
                        if (comp_len[k] < current_min) begin
                            current_min = comp_len[k];
                            current_k   = k;
                        end
                    end
                    
                    optimal_k  <= current_k;
                    //$display("OPTIMAL K CALCULATED: %3d MINIMUM LENGTH: %6d\n", current_k, current_min);

                    min_length <= current_min;
                    done       <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule