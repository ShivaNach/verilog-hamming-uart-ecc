// Noisy serial channel (testbench only, not synthesizable).
// Watches the falling edge of the start bit and then inverts the line during:
//   - data slot k   if flip_mask[k] is 1   (k = 0 is the first data bit sent, LSB of the codeword)
//   - the stop bit  if flip_stop is 1
// Frames must be separated by at least one idle bit period.
module channel #(
    parameter CODE_LEN     = 12,
    parameter CLKS_PER_BIT = 16
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                tx_in,
    input  wire [CODE_LEN-1:0] flip_mask,
    input  wire                flip_stop,
    output wire                rx_out
);
    localparam FRAME_CLKS = (CODE_LEN + 2) * CLKS_PER_BIT; // clock cycles required for start + stop + data to be sent

    reg        prev_tx;
    reg        active;
    reg [$clog2(FRAME_CLKS) - 1:0] cnt;                       // clock cycles since the line fell

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_tx <= 1'b1;
            active  <= 1'b0;
            cnt     <= 0;
        end else begin
            prev_tx <= tx_in;
            if (!active) begin
                if (prev_tx && !tx_in) begin active <= 1'b1; cnt <= 1; end
            end else begin
                cnt <= cnt + 1;
                if (cnt == FRAME_CLKS - 1) active <= 1'b0;
            end
        end
    end

    wire [$clog2(FRAME_CLKS) - 1:0] slot = cnt / CLKS_PER_BIT;            // 0 = start bit, 1..CODE_LEN = data, CODE_LEN+1 = stop
    wire flip = active && (
                    (slot >= 1 && slot <= CODE_LEN && flip_mask[slot - 1]) ||
                    (slot == CODE_LEN + 1 && flip_stop));

    assign rx_out = tx_in ^ flip;
endmodule
