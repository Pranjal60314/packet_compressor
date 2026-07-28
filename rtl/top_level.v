`timescale 1ns / 1ps

module top_level #(
    parameter ADDR_WIDTH  = 10,
    parameter SAMPLE_SIZE = 16,
    parameter PACKAGE_SIZE = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Input Control Interface
    input  wire                    packet_start,        // Assert to begin a full hardware Packet process
    input  wire [ADDR_WIDTH-1:0]   packet_sample_count, // Total samples in the incoming buffer packet
    input  wire [ADDR_WIDTH-1:0]   batch_size,          // Size of 1 Batch (e.g. 16 samples)
    input  wire [ADDR_WIDTH-1:0]   package_size,        // Samples count per reference sample distance
    
    // External Input Port Interfacing
    output reg  [ADDR_WIDTH-1:0]   in_buf_addr,
    input  wire [SAMPLE_SIZE-1:0]   in_buf_data,
    
    // Master Packed Stream Output
    output wire [31:0]             compressed_data,
    output wire                    compressed_we,
    output wire                    pipeline_done
);

    // States
    localparam IDLE         = 3'b000;
    localparam FILL_RAM_0   = 3'b001; // Single-buffer warmup
    localparam FILL_RAM_1   = 3'b010; // Dual-buffer warmup
    localparam STEADY_RUN   = 3'b011; // 3-stage processing steady pipeline 
    localparam DRAIN_STAGE1 = 3'b100; // Emptying the pipeline stages
    localparam DRAIN_STAGE2 = 3'b101; 
    localparam GLOBAL_FLUSH = 3'b110;

    reg [2:0] state;

    // Track total batch/sample boundaries
    reg [ADDR_WIDTH-1:0] samples_loaded;
    reg [ADDR_WIDTH-1:0] samples_estimated;
    reg [ADDR_WIDTH-1:0] samples_encoded;
    reg [ADDR_WIDTH-1:0] batch_count;
    reg [ADDR_WIDTH-1:0] current_batch_sample_cnt;
    reg                  is_reference_batch;

    // Stage 2 evaluation control registers
    reg [ADDR_WIDTH-1:0] stg2_start_addr;
    reg [3:0]            stg2_eval_size;

    // Rotating IDs per stage: 0 = RAM_A, 1 = RAM_B, 2 = RAM_C
    reg [1:0] stage1_ram_id;
    reg [1:0] stage2_ram_id;
    reg [1:0] stage3_ram_id;

    // Reference context sample storage
    reg [SAMPLE_SIZE-1:0] prev_sample_reg;
    reg [ADDR_WIDTH-1:0]  package_sample_counter;

    // Synchronized pipeline stage controllers
    reg        stg1_start, stg2_start, stg3_start;
    wire       stg2_done, stg3_done;
    reg        stg1_busy, stg2_busy, stg3_busy;

    // Optimal K storage context per stage
    reg [7:0]  optimal_k_ping_pong [0:2];

    // Stage 1 Delta Loading control lines
    reg  [ADDR_WIDTH-1:0] stg1_ram_addr;
    wire [SAMPLE_SIZE-1:0] stg1_ram_din;
    reg                    stg1_ram_we;

    // Interconnect wires out of Submodules
    wire [ADDR_WIDTH-1:0] stg2_ram_addr;
    wire [ADDR_WIDTH-1:0] stg3_ram_addr;

    // Individual RAM Interface Signals
    wire [ADDR_WIDTH-1:0]  ramA_addr, ramB_addr, ramC_addr;
    wire [SAMPLE_SIZE-1:0] ramA_din,  ramB_din,  ramC_din;
    wire [SAMPLE_SIZE-1:0] ramA_dout, ramB_dout, ramC_dout;
    wire                   ramA_we,   ramB_we,   ramC_we;

    // ------------------------------------------------------------------------
    // Explicit RAM Instantiations (RAM A, RAM B, RAM C)
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // Direct Signal Multiplexing Based on Stage ID (0=A, 1=B, 2=C)
    // ------------------------------------------------------------------------
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

    // Mux RAM Dout outputs into stage read ports
    wire [SAMPLE_SIZE-1:0] stg2_ram_dout = (stage2_ram_id == 2'd0) ? ramA_dout :
                                           (stage2_ram_id == 2'd1) ? ramB_dout : ramC_dout;

    wire [SAMPLE_SIZE-1:0] stg3_ram_dout = (stage3_ram_id == 2'd0) ? ramA_dout :
                                           (stage3_ram_id == 2'd1) ? ramB_dout : ramC_dout;

    wire is_first_sample_in_batch = (stg1_ram_addr == 0);

    // ------------------------------------------------------------------------
    // Submodule Connections
    // ------------------------------------------------------------------------
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
        .block_size(stg2_eval_size),
        .start_addr(stg2_start_addr), 
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
        .start_addr  ({ADDR_WIDTH{1'b0}}),
        .block_size  (batch_size),
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

    // ------------------------------------------------------------------------
    // Control Flow State Machine
    // ------------------------------------------------------------------------
    assign pipeline_done = (state == IDLE) && !stg1_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= IDLE;
            in_buf_addr            <= 0;

            samples_loaded         <= 0;
            samples_estimated      <= 0;
            samples_encoded        <= 0;
            package_sample_counter <= 0;
            batch_count            <= 0;
            current_batch_sample_cnt <= 0;
            is_reference_batch     <= 1'b0;

            stg2_start_addr        <= 0;
            stg2_eval_size         <= 0;

            prev_sample_reg        <= 0;
            global_flush_en        <= 1'b0;
            
            stage1_ram_id          <= 2'd0;
            stage2_ram_id          <= 2'd1;
            stage3_ram_id          <= 2'd2;

            stg1_start             <= 1'b0;
            stg2_start             <= 1'b0;
            stg3_start             <= 1'b0;

            stg1_busy              <= 1'b0;
            stg2_busy              <= 1'b0;
            stg3_busy              <= 1'b0;
            
            stg1_ram_we            <= 1'b0;
            stg1_ram_addr          <= 0;

            optimal_k_ping_pong[0] <= 8'd0;
            optimal_k_ping_pong[1] <= 8'd0;
            optimal_k_ping_pong[2] <= 8'd0;

        end else begin
            stg1_start      <= 1'b0;
            stg2_start      <= 1'b0;
            stg3_start      <= 1'b0;
            global_flush_en <= 1'b0;

            // Ping-pong optimal k storage handler
            if (stg2_done) begin
                stg2_busy <= 1'b0;
                optimal_k_ping_pong[stage2_ram_id] <= stg2_k_calculated;
            end
            if (stg3_done) begin
                stg3_busy <= 1'b0;
            end

            case (state)
                IDLE: begin
                    if (packet_start) begin
                        samples_loaded           <= 0;
                        samples_estimated        <= 0;
                        samples_encoded          <= 0;
                        package_sample_counter   <= 0;
                        batch_count              <= 0;
                        current_batch_sample_cnt <= 0;
                        is_reference_batch       <= 1'b1;
                        in_buf_addr              <= 0;
                        
                        stage1_ram_id            <= 2'd0;
                        stage2_ram_id            <= 2'd1;
                        stage3_ram_id            <= 2'd2;
                        
                        stg1_busy                <= 1'b1;
                        stg1_ram_addr            <= 0;
                        stg1_ram_we              <= 1'b1;
                        state                    <= FILL_RAM_0;
                    end
                end

                FILL_RAM_0: begin
                    if (stg1_ram_we) begin
                        prev_sample_reg          <= in_buf_data;
                        stg1_ram_addr            <= stg1_ram_addr + 1'b1;
                        in_buf_addr              <= in_buf_addr + 1'b1;
                        samples_loaded           <= samples_loaded + 1'b1;
                        current_batch_sample_cnt <= current_batch_sample_cnt + 1'b1;
                        
                        package_sample_counter   <= (package_sample_counter + 1'b1 >= package_size) ? 0 : package_sample_counter + 1'b1;
                        
                        if (current_batch_sample_cnt + 1'b1 == batch_size) begin
                            stg1_ram_we <= 1'b0;
                            stg1_busy   <= 1'b0;
                        end

                    end else if (!stg1_busy && !stg2_busy && !stg3_busy) begin
                        if (is_reference_batch) begin
                            stg2_eval_size  <= batch_size[3:0] - 1'b1;
                            stg2_start_addr <= 10'd1;
                        end else begin
                            stg2_eval_size  <= batch_size[3:0];
                            stg2_start_addr <= 10'd0;
                        end

                        stage3_ram_id <= stage2_ram_id;
                        stage2_ram_id <= stage1_ram_id;
                        stage1_ram_id <= (stage1_ram_id == 2'd2) ? 2'd0 : stage1_ram_id + 1'b1;
                        
                        batch_count <= batch_count + 1'b1;
                        is_reference_batch <= ((batch_count + 1'b1) % package_size == 0);

                        current_batch_sample_cnt <= 0;
                        stg1_ram_addr <= 0;
                        stg1_ram_we   <= 1'b1;
                        stg1_busy     <= 1'b1;
                        stg2_start    <= 1'b1;
                        stg2_busy     <= 1'b1;
                        state         <= FILL_RAM_1;
                    end
                end

                FILL_RAM_1: begin
                    if (stg1_ram_we) begin
                        prev_sample_reg          <= in_buf_data;
                        stg1_ram_addr            <= stg1_ram_addr + 1'b1;
                        in_buf_addr              <= in_buf_addr + 1'b1;
                        samples_loaded           <= samples_loaded + 1'b1;
                        current_batch_sample_cnt <= current_batch_sample_cnt + 1'b1;
                        
                        package_sample_counter   <= (package_sample_counter + 1'b1 >= package_size) ? 0 : package_sample_counter + 1'b1;
                        
                        if (current_batch_sample_cnt + 1'b1 == batch_size) begin
                            stg1_ram_we <= 1'b0;
                            stg1_busy   <= 1'b0;
                        end

                    end else if (!stg1_busy && !stg2_busy && !stg3_busy) begin
                        samples_estimated <= samples_estimated + batch_size;

                        if (is_reference_batch) begin
                            stg2_eval_size  <= batch_size[3:0] - 1'b1;
                            stg2_start_addr <= 10'd1;
                        end else begin
                            stg2_eval_size  <= batch_size[3:0];
                            stg2_start_addr <= 10'd0;
                        end

                        stage3_ram_id <= stage2_ram_id;
                        stage2_ram_id <= stage1_ram_id;
                        stage1_ram_id <= (stage1_ram_id == 2'd2) ? 2'd0 : stage1_ram_id + 1'b1;
                        
                        batch_count <= batch_count + 1'b1;
                        is_reference_batch <= ((batch_count + 1'b1) % package_size == 0);

                        current_batch_sample_cnt <= 0;
                        stg1_ram_addr <= 0;
                        stg1_ram_we   <= 1'b1;
                        stg1_busy     <= 1'b1;
                        stg2_start    <= 1'b1;
                        stg2_busy     <= 1'b1;
                        stg3_start    <= 1'b1;
                        stg3_busy     <= 1'b1;
                        state         <= STEADY_RUN;
                    end
                end

                STEADY_RUN: begin
                    if (stg1_ram_we) begin
                        prev_sample_reg          <= in_buf_data;
                        stg1_ram_addr            <= stg1_ram_addr + 1'b1;
                        in_buf_addr              <= in_buf_addr + 1'b1;
                        samples_loaded           <= samples_loaded + 1'b1;
                        current_batch_sample_cnt <= current_batch_sample_cnt + 1'b1;
                        
                        package_sample_counter   <= (package_sample_counter + 1'b1 >= package_size) ? 0 : package_sample_counter + 1'b1;
                        
                        if ((current_batch_sample_cnt + 1'b1 == batch_size) || (samples_loaded + 1'b1 >= packet_sample_count)) begin
                            stg1_ram_we <= 1'b0;
                            stg1_busy   <= 1'b0;
                        end
                    
                    end else if (!stg1_busy && !stg2_busy && !stg3_busy) begin
                        samples_estimated <= samples_estimated + batch_size;
                        samples_encoded   <= samples_encoded + batch_size;
                        
                        if (samples_loaded >= packet_sample_count) begin
                            stage3_ram_id <= stage2_ram_id;
                            stage2_ram_id <= stage1_ram_id;
                            
                            stg2_start    <= 1'b1;
                            stg2_busy     <= 1'b1;
                            stg3_start    <= 1'b1;
                            stg3_busy     <= 1'b1;
                            state         <= DRAIN_STAGE1;
                        end else begin
                            if (is_reference_batch) begin
                                stg2_eval_size  <= batch_size[3:0] - 1'b1;
                                stg2_start_addr <= 10'd1;
                            end else begin
                                stg2_eval_size  <= batch_size[3:0];
                                stg2_start_addr <= 10'd0;
                            end

                            stage3_ram_id <= stage2_ram_id;
                            stage2_ram_id <= stage1_ram_id;
                            stage1_ram_id <= (stage1_ram_id == 2'd2) ? 2'd0 : stage1_ram_id + 1'b1;
                            
                            batch_count <= batch_count + 1'b1;
                            is_reference_batch <= ((batch_count + 1'b1) % package_size == 0);

                            current_batch_sample_cnt <= 0;
                            stg1_ram_addr <= 0;
                            stg1_ram_we   <= 1'b1;
                            stg1_busy     <= 1'b1;
                            stg2_start    <= 1'b1;
                            stg2_busy     <= 1'b1;
                            stg3_start    <= 1'b1;
                            stg3_busy     <= 1'b1;
                        end
                    end
                end

                DRAIN_STAGE1: begin
                    if (!stg2_busy && !stg3_busy) begin
                        samples_estimated <= samples_estimated + batch_size;
                        samples_encoded   <= samples_encoded + batch_size;
                        
                        stage3_ram_id <= stage2_ram_id;
                        stg3_start    <= 1'b1;
                        stg3_busy     <= 1'b1;
                        state         <= DRAIN_STAGE2;
                    end
                end

                DRAIN_STAGE2: begin
                    if (!stg3_busy) begin
                        samples_encoded <= samples_encoded + batch_size;
                        global_flush_en <= 1'b1;
                        state           <= GLOBAL_FLUSH;
                    end
                end

                GLOBAL_FLUSH: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule