module uart_tx #(
    parameter WIDTH        = 12,
    parameter CLKS_PER_BIT = CLK_FREQ / BAUD
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] data_in,
    input  wire             start,
    output reg              tx,
    output wire             busy
);
    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]                         state;
    reg [$clog2(CLKS_PER_BIT)-1:0]  count;    // clock cycles within the current bit
    reg [$clog2(WIDTH+1)-1:0]         index;    // which data bit is on the wire

    assign busy = (state != IDLE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx    <= 1'b1;
            count <= 0;
            index <= 0;
        end else begin
            case (state)

                IDLE: begin
                    tx    <= 1'b1;
                    count <= 0;
                    index <= 0;
                    if (start) begin
                        tx    <= 1'b0;          // start bit begins now
                        state <= START;
                    end
                end

                START: begin                    // tx is 0 for one full bit period
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        state <= DATA;
                        tx <= data_in[0];
                        index <= index + 1; 
                    end else
                        count <= count + 1;
                end

                DATA: begin
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        if (index == WIDTH) begin   // last data bit just finished
                            tx    <= 1'b1;              // stop bit
                            state <= STOP;
                        end else begin
                            tx    <= data_in[index];
                            index <= index + 1;
                        end
                    end else begin
                        count <= count + 1;
                    end
                end

                STOP: begin                     // tx is 1 for one full bit period
                    if (count == CLKS_PER_BIT - 1) begin
                        count <= 0;
                        state <= IDLE;
                    end else
                        count <= count + 1;
                end

            endcase
        end
    end
endmodule