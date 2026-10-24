module hamming_dec #(
    parameter DATA_LEN = 8,
    parameter PARITIES = $clog2(DATA_LEN) + 1,
    parameter CODE_LEN = DATA_LEN + PARITIES
)(
    input  wire [CODE_LEN-1:0] code_in,
    output wire [DATA_LEN-1:0] data_out,
    output wire is_error
);
    wire [PARITIES-1:0] syndrome;
    genvar pos, i;

    // 1. syndrome bit i = XOR of all received bits whose position has bit i set
    generate
        for (i = 0; i < PARITIES; i = i + 1) begin : syn
            wire [CODE_LEN-1:0] covered;
            for (pos = 1; pos <= CODE_LEN; pos = pos + 1) begin : m
                if ((pos >> i) & 1)
                    assign covered[pos-1] = code_in[pos-1];
                else
                    assign covered[pos-1] = 1'b0;
            end
            assign syndrome[i] = ^covered;
        end
    endgenerate

    // 2. flag and correction
    assign is_error = (syndrome != 0);
    wire [CODE_LEN-1:0] corrected;
    assign corrected = code_in ^ (is_error ? (1 << (syndrome - 1)) : {CODE_LEN{1'b0}}); //bitmask depending on error flag
    // 3. pull data bits back out of the non-power-of-two positions
    generate
        for (pos = 1; pos <= CODE_LEN; pos = pos + 1) begin : extract
            if ((pos & (pos - 1)) != 0)
                assign data_out[pos - $clog2(pos) - 1] = corrected[pos-1];
        end
    endgenerate
endmodule