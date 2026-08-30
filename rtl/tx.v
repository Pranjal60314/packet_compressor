module buffered_uart_tx #(
    parameter BIT_RATE = 9600,
    parameter CLK_HZ   = 50000000,
    parameter FIFO_DEPTH = 32
)(
    input wire clk,
    input wire resetn,

    input wire tx_en,
    
    // Interface to HDR module
    input  wire [7:0] wr_data,
    input  wire wr_en,
    output wire fifo_full,
    
    // Physical Line
    output wire uart_txd,
    output wire tx_busy      // System is busy if FIFO has data OR UART is transmitting
);

    wire [7:0] fifo_dout;
    wire fifo_empty;
    reg fifo_rd_en;
    wire uart_busy;
    reg uart_en;

    // 1. Instantiate the FIFO
    fifo #(.DEPTH(FIFO_DEPTH), .WIDTH(8)) tx_buffer (
        .clk(clk),
        .rst(!resetn), // Convert to active high for your FIFO
        .wr_en(wr_en),
        .rd_en(fifo_rd_en),
        .din(wr_data),
        .dout(fifo_dout),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    // 2. Instantiate your UART TX
    uart_tx #(
        .BIT_RATE(BIT_RATE),
        .CLK_HZ(CLK_HZ)
    ) physical_tx (
        .clk(clk),
        .resetn(resetn),
        .uart_txd(uart_txd),
        .uart_tx_busy(uart_busy),
        .uart_tx_en(uart_en),
        .uart_tx_data(fifo_dout)
    );

typedef enum reg [1:0] {IDLE, PREFETCH, START_UART, WAIT_BUSY} state_t;
    state_t state;

reg fsm_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            fifo_rd_en <= 0;
            uart_en    <= 0;
            fsm_busy   <= 0; 
            state      <= IDLE;
        end else begin
            fifo_rd_en <= 0;
            uart_en    <= 0;

            case (state)
                IDLE: begin
                    if (tx_en && !fifo_empty && !uart_busy) begin
                        fifo_rd_en <= 1;
                        fsm_busy   <= 1; 
                        state      <= PREFETCH;
                    end else if (!uart_busy) begin
                        fsm_busy   <= 0; 
                    end
                end

                PREFETCH: begin
                    fsm_busy <= 1;
                    state    <= START_UART;
                end

                START_UART: begin
                    fsm_busy <= 1;
                    uart_en  <= 1;
                    state    <= WAIT_BUSY;
                end

                WAIT_BUSY: begin
                    fsm_busy <= 1;
                    if (uart_busy) begin
                        state <= IDLE; 
                    end
                end
            endcase
        end
    end
    
    assign tx_busy = uart_busy || !fifo_empty || fsm_busy; 

endmodule

// module fifo #(
//     parameter DEPTH = 32,
//     parameter WIDTH = 8
// )(
//     input wire clk,
//     input wire rst,

//     input wire wr_en,
//     input wire rd_en,
//     input wire [WIDTH-1:0] din,

//     output reg [WIDTH-1:0] dout,
//     output wire full,
//     output wire empty
// );
//     reg [WIDTH-1:0] mem [0:DEPTH-1];
//     reg [$clog2(DEPTH):0] wr_ptr, rd_ptr;

//     assign empty = (wr_ptr == rd_ptr);
//     assign full  = (wr_ptr - rd_ptr == DEPTH);

//     always @(posedge clk) begin
//         if (rst) begin
//             wr_ptr <= 0;
//             rd_ptr <= 0;
//         end else begin
//             // write
//             if (wr_en && !full) begin
//                 mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
//                 wr_ptr <= wr_ptr + 1;
//             end

//             // read
//             if (rd_en && !empty) begin
//                 dout <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
//                 rd_ptr <= rd_ptr + 1;
//             end
//         end
//     end

// endmodule

module uart_tx
#(
    parameter   BIT_RATE        = 9600, // bits / sec
    parameter   CLK_HZ          = 50_000_000,
    parameter   PAYLOAD_BITS    = 8,
    parameter   STOP_BITS       = 1
)(
input  wire         clk         , // Top level system clock input.
input  wire         resetn      , // Asynchronous active low reset.
output wire         uart_txd    , // UART transmit pin.
output wire         uart_tx_busy, // Module busy sending previous item.
input  wire         uart_tx_en  , // Send the data on uart_tx_data
input  wire [PAYLOAD_BITS-1:0]   uart_tx_data  // The data to be sent
);

// Input bit rate of the UART line.
//parameter   BIT_RATE        = 9600; // bits / sec
localparam  BIT_P           = 1_000_000_000 * 1/BIT_RATE; // nanoseconds

// Clock frequency in hertz.
//parameter   CLK_HZ          =    50_000_000;
localparam  CLK_P           = 1_000_000_000 * 1/CLK_HZ; // nanoseconds

// Number of data bits recieved per UART packet.
//parameter   PAYLOAD_BITS    = 8;

// Number of stop bits indicating the end of a packet.
//parameter   STOP_BITS       = 1;

//
// Number of clock cycles per uart bit.
localparam       CYCLES_PER_BIT     = BIT_P / CLK_P;

// Size of the registers which store sample counts and bit durations.
localparam       COUNT_REG_LEN      = 1+$clog2(CYCLES_PER_BIT);

// Internally latched value of the uart_txd line. Helps break long timing
// paths from the logic to the output pins.
reg txd_reg;

// Storage for the serial data to be sent.
reg [PAYLOAD_BITS-1:0] data_to_send;

// Counter for the number of cycles over a packet bit.
reg [COUNT_REG_LEN-1:0] cycle_counter;

//
// Counter for the number of sent bits of the packet.
reg [3:0] bit_counter;

// Current and next states of the internal FSM.
reg [2:0] fsm_state;
reg [2:0] n_fsm_state;

localparam FSM_IDLE = 0;
localparam FSM_START= 1;
localparam FSM_SEND = 2;
localparam FSM_STOP = 3;

assign uart_tx_busy = fsm_state != FSM_IDLE;
assign uart_txd     = txd_reg;

wire next_bit     = cycle_counter == CYCLES_PER_BIT;
wire payload_done = bit_counter   == PAYLOAD_BITS  ;
wire stop_done    = bit_counter   == STOP_BITS && fsm_state == FSM_STOP;

// Handle picking the next state.
always @(*) begin : p_n_fsm_state
    case(fsm_state)
        FSM_IDLE : n_fsm_state = uart_tx_en   ? FSM_START: FSM_IDLE ;
        FSM_START: n_fsm_state = next_bit     ? FSM_SEND : FSM_START;
        FSM_SEND : n_fsm_state = payload_done ? FSM_STOP : FSM_SEND ;
        FSM_STOP : n_fsm_state = stop_done    ? FSM_IDLE : FSM_STOP ;
        default  : n_fsm_state = FSM_IDLE;
    endcase
end

// Handle updates to the sent data register.
integer i = 0;
always @(posedge clk) begin : p_data_to_send
    if(!resetn) begin
        data_to_send <= {PAYLOAD_BITS{1'b0}};
    end else if(fsm_state == FSM_IDLE && uart_tx_en) begin
        data_to_send <= uart_tx_data;
    end else if(fsm_state       == FSM_SEND       && next_bit ) begin
        for ( i = PAYLOAD_BITS-2; i >= 0; i = i - 1) begin
            data_to_send[i] <= data_to_send[i+1];
        end
    end
end

// Increments the bit counter each time a new bit frame is sent.
always @(posedge clk) begin : p_bit_counter
    if(!resetn) begin
        bit_counter <= 4'b0;
    end else if(fsm_state != FSM_SEND && fsm_state != FSM_STOP) begin
        bit_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(fsm_state == FSM_SEND && n_fsm_state == FSM_STOP) begin
        bit_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(fsm_state == FSM_STOP&& next_bit) begin
        bit_counter <= bit_counter + 1'b1;
    end else if(fsm_state == FSM_SEND && next_bit) begin
        bit_counter <= bit_counter + 1'b1;
    end
end

// Increments the cycle counter when sending.
always @(posedge clk) begin : p_cycle_counter
    if(!resetn) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(next_bit) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if(fsm_state == FSM_START || 
                fsm_state == FSM_SEND  || 
                fsm_state == FSM_STOP   ) begin
        cycle_counter <= cycle_counter + 1'b1;
    end
end

// Progresses the next FSM state.
always @(posedge clk) begin : p_fsm_state
    if(!resetn) begin
        fsm_state <= FSM_IDLE;
    end else begin
        fsm_state <= n_fsm_state;
    end
end

// Responsible for updating the internal value of the txd_reg.
always @(posedge clk) begin : p_txd_reg
    if(!resetn) begin
        txd_reg <= 1'b1;
    end else if(fsm_state == FSM_IDLE) begin
        txd_reg <= 1'b1;
    end else if(fsm_state == FSM_START) begin
        txd_reg <= 1'b0;
    end else if(fsm_state == FSM_SEND) begin
        txd_reg <= data_to_send[0];
    end else if(fsm_state == FSM_STOP) begin
        txd_reg <= 1'b1;
    end
end

endmodule
