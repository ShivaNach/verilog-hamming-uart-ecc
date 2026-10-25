module hamming_enc #(
    parameter DATA_LEN = 8,
    parameter PARITIES = $clog2(DATA_LEN) + 1, //NOTE: MUST BE 2^n ELSE WOULD FAIL 
    parameter CODE_LEN = DATA_LEN + PARITIES 
)(
    input  wire [DATA_LEN-1:0] data_in,
    output wire [CODE_LEN-1:0] code_out
);
    genvar pos, i;
    generate
        // data bits: a plain wire connection at each non-power-of-two position
        for (pos = 1; pos <= CODE_LEN; pos = pos + 1) begin : place
            if ((pos & (pos - 1)) != 0) //logic to check not power of two 
                assign code_out[pos-1] = data_in[pos - $clog2(pos) - 1]; //subtracting no of parities covered to shift position
        end
        // parity bits: one XOR tree each
        for (i = 0; i < PARITIES; i = i + 1) begin : par
            wire [CODE_LEN-1:0] covered;
            for (pos = 1; pos <= CODE_LEN; pos = pos + 1) begin : m
                if ((pos & (pos - 1)) != 0 && ((pos >> i) & 1)) //no power of 2, and ith bit is set (pos >> i) & 1
                    assign covered[pos-1] = code_out[pos-1];
                else
                    assign covered[pos-1] = 1'b0;
            end
            assign code_out[(1 << i) - 1] = ^covered;
        end
    endgenerate
endmodule