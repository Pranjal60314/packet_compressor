`timescale 1ns / 1ps

module top_level #(
    parameter ADDR_WIDTH   = 10,
    parameter SAMPLE_SIZE  = 16,
    parameter PACKAGE_SIZE = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    packet_start,                                                         
    input  wire [ADDR_WIDTH-1:0]   packet_sample_count,                                               
    input  wire [ADDR_WIDTH-1:0]   batch_size,                                              
    input  wire [ADDR_WIDTH-1:0]   package_size,                                                      
    
    output reg  [ADDR_WIDTH-1:0]   in_buf_addr,
    input  wire [SAMPLE_SIZE-1:0]   in_buf_data,
    
    output wire [31:0]             compressed_data,
    output wire                    compressed_we,
    output wire                    pipeline_done
);

    localparam RAM_FREE      = 2'b00,
               RAM_STG1_DONE = 2'b01,
               RAM_STG2_DONE = 2'b10;

    reg [1:0] ram_state    [0:2];
    reg       ram_ref_flag [0:2];

    reg [1:0] stage1_ram_id;
    reg [1:0] stage2_ram_id;
    reg [1:0] stage3_ram_id;

    reg [ADDR_WIDTH-1:0] samples_loaded;
    reg [ADDR_WIDTH-1:0] samples_encoded;
    reg [ADDR_WIDTH-1:0] batch_count;
    reg [ADDR_WIDTH-1:0] current_batch_sample_cnt;
    reg                  is_reference_batch;

    reg [ADDR_WIDTH-1:0] stg2_start_addr;
    reg [ADDR_WIDTH-1:0] stg2_eval_size;

    reg [ADDR_WIDTH-1:0] stg3_start_addr;
    reg [ADDR_WIDTH-1:0] stg3_eval_size;

    reg [SAMPLE_SIZE-1:0] prev_sample_reg;
    reg [ADDR_WIDTH-1:0]  package_sample_counter;

    reg        stg1_start, stg2_start, stg3_start;
    wire       stg2_done, stg3_done;
    reg        stg1_busy, stg2_busy, stg3_busy;

    reg [7:0]  optimal_k_ping_pong [0:2];

    reg  [ADDR_WIDTH-1:0]  stg1_ram_addr;
    wire [SAMPLE_SIZE-1:0] stg1_ram_din;
    reg                    stg1_ram_we;

    wire [ADDR_WIDTH-1:0] stg2_ram_addr;
    wire [ADDR_WIDTH-1:0] stg3_ram_addr;

    wire [ADDR_WIDTH-1:0]  ramA_addr, ramB_addr, ramC_addr;
    wire [SAMPLE_SIZE-1:0] ramA_din,  ramB_din,  ramC_din;
    wire [SAMPLE_SIZE-1:0] ramA_dout, ramB_dout, ramC_dout;
    wire                   ramA_we,   ramB_we,   ramC_we;

    ram #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ram_A (
        .clk (clk),
        .we  (ramA_we),
        .addr(ramA_addr),
        .din (ramA_din),
        .dout(ramA_dout)
    );

    ram #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ram_B (
        .clk (clk),
        .we  (ramB_we),
        .addr(ramB_addr),
        .din (ramB_din),
        .dout(ramB_dout)
    );

    ram #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ram_C (
        .clk (clk),
        .we  (ramC_we),
        .addr(ramC_addr),
        .din (ramC_din),
        .dout(ramC_dout)
    );

    assign ramA_we   = (stage1_ram_id == 2'd0) ? stg1_ram_we   : 1'b0;
    assign ramA_addr = (stage1_ram_id == 2'd0) ? stg1_ram_addr :
                       (stage2_ram_id == 2'd0) ? stg2_ram_addr : stg3_ram_addr;
    assign ramA_din  = (stage1_ram_id == 2'd0) ? stg1_ram_din  : {SAMPLE_SIZE{1'b0}};

    assign ramB_we   = (stage1_ram_id == 2'd1) ? stg1_ram_we   : 1'b0;
    assign ramB_addr = (stage1_ram_id == 2'd1) ? stg1_ram_addr :
                       (stage2_ram_id == 2'd1) ? stg2_ram_addr : stg3_ram_addr;
    assign ramB_din  = (stage1_ram_id == 2'd1) ? stg1_ram_din  : {SAMPLE_SIZE{1'b0}};

    assign ramC_we   = (stage1_ram_id == 2'd2) ? stg1_ram_we   : 1'b0;
    assign ramC_addr = (stage1_ram_id == 2'd2) ? stg1_ram_addr :
                       (stage2_ram_id == 2'd2) ? stg2_ram_addr : stg3_ram_addr;
    assign ramC_din  = (stage1_ram_id == 2'd2) ? stg1_ram_din  : {SAMPLE_SIZE{1'b0}};

    wire [SAMPLE_SIZE-1:0] stg2_ram_dout = (stage2_ram_id == 2'd0) ? ramA_dout :
                                           (stage2_ram_id == 2'd1) ? ramB_dout : ramC_dout;

    wire [SAMPLE_SIZE-1:0] stg3_ram_dout = (stage3_ram_id == 2'd0) ? ramA_dout :
                                           (stage3_ram_id == 2'd1) ? ramB_dout : ramC_dout;

    wire is_first_sample_in_batch = (stg1_ram_addr == 0);

    wire [SAMPLE_SIZE-1:0] stg1_delta_out;
    
    delta_processing delta_unit (
        .previous_x   (prev_sample_reg),
        .current_x    (in_buf_data),
        .encoded_delta(stg1_delta_out)
    );

    assign stg1_ram_din = (is_reference_batch && is_first_sample_in_batch) 
                          ? in_buf_data 
                          : stg1_delta_out;

    wire [7:0] stg2_k_calculated;
    wire [3:0] k_est_mem_addr;
    assign stg2_ram_addr = stg2_start_addr + { {(ADDR_WIDTH-4){1'b0}}, k_est_mem_addr };

    k_estimation #(
        .SAMPLE_SIZE(SAMPLE_SIZE)
    ) k_estimator (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (stg2_start),
        .block_size(stg2_eval_size[3:0]),
        .start_addr(stg2_start_addr[3:0]), 
        .done      (stg2_done),
        .optimal_k (stg2_k_calculated),
        .min_length(),
        .mem_addr  (k_est_mem_addr),
        .mem_data  (stg2_ram_dout)
    );

    wire        pack_en_wire;
    wire [31:0] pack_bits_wire;
    wire [5:0]  pack_count_wire;
    wire        packer_ready_wire;
    reg         global_flush_en;

    encoder #(
        .SAMPLE_SIZE(SAMPLE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) block_encoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (stg3_start),
        .done        (stg3_done),
        .encoder_busy(),
        .start_addr  (stg3_start_addr), 
        .block_size  (stg3_eval_size),  
        .is_reference(ram_ref_flag[stage3_ram_id]),
        .optimal_k   (optimal_k_ping_pong[stage3_ram_id]),
        .ram_addr    (stg3_ram_addr),
        .ram_data    (stg3_ram_dout),
        .pack_en     (pack_en_wire),
        .pack_bits   (pack_bits_wire),
        .pack_count  (pack_count_wire),
        .packer_ready(packer_ready_wire)
    );

    bit_pack master_packer (
        .clk         (clk),
        .rst_n       (rst_n),
        .pack_en     (pack_en_wire),
        .flush_en    (global_flush_en),
        .bits        (pack_bits_wire),
        .count       (pack_count_wire),
        .ram_data    (compressed_data),
        .ram_we      (compressed_we),
        .packer_ready(packer_ready_wire)
    );

    assign pipeline_done = !stg1_busy && !stg2_busy && !stg3_busy &&
                           (ram_state[0] == RAM_FREE) &&
                           (ram_state[1] == RAM_FREE) &&
                           (ram_state[2] == RAM_FREE);

    localparam S1_IDLE = 1'b0, S1_RUN = 1'b1;
    reg s1_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_state                 <= S1_IDLE;
            in_buf_addr              <= 0;
            samples_loaded           <= 0;
            current_batch_sample_cnt <= 0;
            batch_count              <= 0;
            package_sample_counter   <= 0;
            is_reference_batch       <= 1'b1;
            prev_sample_reg          <= 0;
            stage1_ram_id            <= 2'd0;
            stg1_ram_addr            <= 0;
            stg1_ram_we              <= 1'b0;
            stg1_busy                <= 1'b0;
        end else begin
            case (s1_state)
                S1_IDLE: begin
                    if (packet_start) begin
                        samples_loaded           <= 0;
                        current_batch_sample_cnt <= 0;
                        batch_count              <= 0;
                        package_sample_counter   <= 0;
                        is_reference_batch       <= 1'b1;
                        in_buf_addr              <= 0;
                        stage1_ram_id            <= 2'd0;
                        
                        if (ram_state[2'd0] == RAM_FREE) begin
                            stg1_ram_addr <= 0;
                            stg1_ram_we   <= 1'b1;
                            stg1_busy     <= 1'b1;
                            s1_state      <= S1_RUN;
                        end else begin
                            stg1_busy     <= 1'b1;                               
                        end
                    end else if (samples_loaded < packet_sample_count) begin
                        if (ram_state[stage1_ram_id] == RAM_FREE) begin
                            stg1_ram_addr <= 0;
                            stg1_ram_we   <= 1'b1;
                            stg1_busy     <= 1'b1;
                            s1_state      <= S1_RUN;
                        end else begin
                            stg1_ram_we   <= 1'b0;
                            stg1_busy     <= 1'b1;               
                        end
                    end else begin
                        stg1_ram_we       <= 1'b0;
                        stg1_busy         <= 1'b0;
                    end
                end

                S1_RUN: begin
                    if (stg1_ram_we) begin
                        prev_sample_reg          <= in_buf_data;
                        stg1_ram_addr            <= stg1_ram_addr + 1'b1;
                        in_buf_addr              <= in_buf_addr + 1'b1;
                        samples_loaded           <= samples_loaded + 1'b1;
                        current_batch_sample_cnt <= current_batch_sample_cnt + 1'b1;
                        package_sample_counter   <= (package_sample_counter + 1'b1 >= package_size) ? 0 : package_sample_counter + 1'b1;

                        if ((current_batch_sample_cnt + 1'b1 == batch_size) || (samples_loaded + 1'b1 >= packet_sample_count)) begin
                            stg1_ram_we <= 1'b0;

                            batch_count              <= batch_count + 1'b1;
                            is_reference_batch       <= ((batch_count + 1'b1) % package_size == 0);
                            current_batch_sample_cnt <= 0;

                            stage1_ram_id            <= (stage1_ram_id == 2'd2) ? 2'd0 : stage1_ram_id + 1'b1;
                            s1_state                  <= S1_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    localparam S2_IDLE        = 2'b00,
               S2_CLAIM_RAM   = 2'b01,
               S2_PULSE_START = 2'b10,
               S2_WAIT_DONE   = 2'b11;

    reg [1:0] s2_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_state              <= S2_IDLE;
            stage2_ram_id         <= 2'd0;
            stg2_start_addr       <= {ADDR_WIDTH{1'b0}};
            stg2_eval_size        <= 4'd0;
            stg2_start            <= 1'b0;
            stg2_busy             <= 1'b0;
            optimal_k_ping_pong[0]<= 8'd0;
            optimal_k_ping_pong[1]<= 8'd0;
            optimal_k_ping_pong[2]<= 8'd0;
        end else begin
            stg2_start <= 1'b0; 

            case (s2_state)
                S2_IDLE: begin
                    if (packet_start) begin
                        stage2_ram_id <= 2'd0;
                        stg2_busy     <= 1'b0;
                    end else if (ram_state[stage2_ram_id] == RAM_STG1_DONE) begin
                        stg2_busy <= 1'b1;

                        if (ram_ref_flag[stage2_ram_id]) begin
                            stg2_eval_size  <= batch_size - 1'b1;
                            stg2_start_addr <= { {(ADDR_WIDTH-1){1'b0}}, 1'b1 };
                        end else begin
                            stg2_eval_size  <= batch_size;
                            stg2_start_addr <= {ADDR_WIDTH{1'b0}};
                        end

                        s2_state <= S2_CLAIM_RAM;
                    end else begin
                        stg2_busy <= 1'b0;
                    end
                end

                S2_CLAIM_RAM:   s2_state <= S2_PULSE_START;

                S2_PULSE_START: begin
                    stg2_start <= 1'b1;
                    s2_state   <= S2_WAIT_DONE;
                end

                S2_WAIT_DONE: begin
                    if (stg2_done) begin
                        $display("[STAGE 2] Optimal k for RAM ID %0d: %0d\n", stage2_ram_id, stg2_k_calculated);
                        optimal_k_ping_pong[stage2_ram_id] <= stg2_k_calculated;

                        stage2_ram_id <= (stage2_ram_id == 2'd2) ? 2'd0 : stage2_ram_id + 1'b1;
                        s2_state      <= S2_IDLE;
                    end
                end

                default: s2_state <= S2_IDLE;
            endcase
        end
    end

    localparam S3_IDLE        = 3'b000,
               S3_CLAIM_RAM   = 3'b001,
               S3_PULSE_START = 3'b010,
               S3_WAIT_DONE   = 3'b011,
               S3_FLUSH       = 3'b100;

    reg [2:0] s3_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_state        <= S3_IDLE;
            stage3_ram_id   <= 2'd0;
            samples_encoded <= 0;
            stg3_start      <= 1'b0;
            stg3_busy       <= 1'b0;
            global_flush_en <= 1'b0;
            stg3_start_addr <= {ADDR_WIDTH{1'b0}};
            stg3_eval_size  <= {ADDR_WIDTH{1'b0}};
        end else begin
            stg3_start      <= 1'b0;
            global_flush_en <= 1'b0;

            case (s3_state)
                S3_IDLE: begin
                    if (packet_start) begin
                        samples_encoded <= 0;
                        stage3_ram_id   <= 2'd0;
                        stg3_busy       <= 1'b0;
                    end else if (ram_state[stage3_ram_id] == RAM_STG2_DONE) begin
                        stg3_busy <= 1'b1;

                        if (ram_ref_flag[stage3_ram_id]) begin
                            stg3_eval_size  <= batch_size - 1'b1;
                            stg3_start_addr <= { {(ADDR_WIDTH-1){1'b0}}, 1'b1 };
                        end else begin
                            stg3_eval_size  <= batch_size;
                            stg3_start_addr <= {ADDR_WIDTH{1'b0}};
                        end

                        s3_state <= S3_CLAIM_RAM;
                    end else begin
                        stg3_busy <= 1'b0;
                    end
                end

                S3_CLAIM_RAM:   s3_state <= S3_PULSE_START;

                S3_PULSE_START: begin
                    stg3_start <= 1'b1;
                    s3_state   <= S3_WAIT_DONE;
                end

                S3_WAIT_DONE: begin
                    if (stg3_done) begin
                        samples_encoded <= samples_encoded + batch_size;
                        $display("[STAGE 3] Encoding complete for RAM ID %0d. Total Encoded: %0d\n", stage3_ram_id, samples_encoded + batch_size);

                        stage3_ram_id <= (stage3_ram_id == 2'd2) ? 2'd0 : stage3_ram_id + 1'b1;

                        if (samples_encoded + batch_size >= packet_sample_count) begin
                            global_flush_en <= 1'b1;                               
                            s3_state        <= S3_FLUSH;
                        end else begin
                            s3_state        <= S3_IDLE;
                        end
                    end
                end

                S3_FLUSH: begin
                    stg3_busy <= 1'b0;
                    s3_state  <= S3_IDLE;
                end

                default: s3_state <= S3_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_state[0]    <= RAM_FREE;
            ram_state[1]    <= RAM_FREE;
            ram_state[2]    <= RAM_FREE;
            ram_ref_flag[0] <= 1'b0;
            ram_ref_flag[1] <= 1'b0;
            ram_ref_flag[2] <= 1'b0;
        end else if (packet_start) begin
            ram_state[0]    <= RAM_FREE;
            ram_state[1]    <= RAM_FREE;
            ram_state[2]    <= RAM_FREE;
            ram_ref_flag[0] <= 1'b0;
            ram_ref_flag[1] <= 1'b0;
            ram_ref_flag[2] <= 1'b0;
        end else begin
            if ((s1_state == S1_RUN) && stg1_ram_we && 
               ((current_batch_sample_cnt + 1'b1 == batch_size) || (samples_loaded + 1'b1 >= packet_sample_count))) begin
                ram_state[stage1_ram_id]    <= RAM_STG1_DONE;
                ram_ref_flag[stage1_ram_id] <= is_reference_batch;
            end
                                            
            if ((s2_state == S2_WAIT_DONE) && stg2_done) begin
                ram_state[stage2_ram_id] <= RAM_STG2_DONE;
            end
                                
            if ((s3_state == S3_WAIT_DONE) && stg3_done) begin
                ram_state[stage3_ram_id] <= RAM_FREE;
            end
        end
    end

endmodule