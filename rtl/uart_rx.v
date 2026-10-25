module uart_rx #(
    parameter WIDTH        = 12,
    parameter BAUD         = 9600,
    parameter CLK_FREQ     = 50_000_000,
    parameter CLKS_PER_BIT = CLK_FREQ / BAUD
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             rx,
    output reg  [WIDTH-1:0] data_out, // only meaninful when valid is HIGH
    output reg              valid,         // one-cycle pulse: a good frame just arrived
    output reg              frame_error    // one-cycle pulse: stop bit was not HIGH
);
    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]                         state;
    reg [$clog2(CLKS_PER_BIT)-1:0]  count;    // clock cycles within the current bit
    reg [$clog2(WIDTH)-1:0]         index;    // which data bit we are collecting

    // rx comes from outside our clock domain: pass it through two flip-flops first (acts like a synchroniser to handle metastable states)
    reg rx_meta, rx_sync;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            count       <= 0;
            index       <= 0;
            data_out    <= 0;
            valid       <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            valid       <= 1'b0;                // pulses: low unless set below
            frame_error <= 1'b0;

            case (state)

                IDLE: begin                     // line is HIGH; wait for the falling edge
                    count <= 0;
                    index <= 0;
                    if (!rx_sync)
                        state <= START;
                end

                START: begin                    // wait half a bit, then re-check the line
                    if (count == CLKS_PER_BIT/2 - 1) begin
                        count <= 0;
                        if (!rx_sync)
                            state <= DATA;      // still low: a real start bit
                        else
                            state <= IDLE;      // it was a glitch, ignore it (start bit had to be low for the agreed upon pulse)
                    end else
                        count <= count + 1;
                end

                DATA: begin                     // one full bit later = middle of each data bit
                    if (count == CLKS_PER_BIT - 1) begin
                        count        <= 0;
                        data_out[index] <= rx_sync;
                        if (index == WIDTH - 1)
                            state <= STOP;
                        else
                            index <= index + 1;
                    end else
                        count <= count + 1;
                end

                STOP: begin                     // middle of the stop bit
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        state <= IDLE;
                        if (rx_sync) begin
                            valid    <= 1'b1;
                        end else
                            frame_error <= 1'b1;
                    end else
                        count <= count + 1;
                end

            endcase
        end
    end
endmodule