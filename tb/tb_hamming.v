// Exhaustive test of hamming_enc_gen + hamming_dec (no clock, no UART).
//   no error      : data comes back unchanged, is_error = 0
//   every 1-bit   : data corrected, is_error = 1   (all codeword positions, parity bits included)
//   every 2-bit   : is_error = 1 (always noticed); data is NOT trusted - the count of
//                   silently mis-corrected words is printed as a known limitation of plain Hamming
`timescale 1ns/1ps

module hamming_check #(
    parameter W      = 8,
    parameter STRIDE = 1                 // test every STRIDE-th data word in the 2-bit sweep
)(
    output reg done,
    output reg failed
);
    localparam P = $clog2(W) + 1;
    localparam C = W + P;

    reg  [W-1:0] d; // data to be sent
    wire [C-1:0] code;
    reg  [C-1:0] rx; // separate code sent to the decoder to simulate corruption of data
    wire [W-1:0] q; // output data (ideally same as input, but can be corrupted with 2 bit or more error)
    wire         err;

    hamming_enc #(.DATA_LEN(W)) enc (.data_in(d),  .code_out(code));
    hamming_dec #(.DATA_LEN(W)) dec (.code_in(rx), .data_out(q), .is_error(err));

    integer k, a, b;
    integer n0 = 0, n0_bad = 0, n1 = 0, n1_bad = 0, n2 = 0, n2_missed = 0, n2_wrong = 0;

    initial begin
        done = 0; failed = 0;
        for (k = 0; k < (1 << W); k = k + 1) begin
            d = k; #1;

            rx = code; #1;                                         // no error
            n0 = n0 + 1;
            if (q !== d || err !== 1'b0) n0_bad = n0_bad + 1;

            for (a = 0; a < C; a = a + 1) begin                    // every single flip
                rx = code ^ (1 << a); #1;
                n1 = n1 + 1;
                if (q !== d || err !== 1'b1) n1_bad = n1_bad + 1;
            end

            if (k % STRIDE == 0)
                for (a = 0; a < C; a = a + 1)                      // every double flip
                    for (b = a + 1; b < C; b = b + 1) begin
                        rx = code ^ (1 << a) ^ (1 << b); #1;
                        n2 = n2 + 1;
                        if (err !== 1'b1) n2_missed = n2_missed + 1;
                        if (q !== d)      n2_wrong  = n2_wrong + 1;
                    end
        end
        $display("[hamming W=%0d, %0d-bit codeword]", W, C);
        $display("   no error : %0d cases, %0d failures", n0, n0_bad);
        $display("   1-bit    : %0d cases, %0d failures (all corrected, all flagged)", n1, n1_bad);
        $display("   2-bit    : %0d cases, %0d not flagged, %0d returned wrong data (expected for plain Hamming)",
                 n2, n2_missed, n2_wrong);
        failed = (n0_bad != 0) || (n1_bad != 0) || (n2_missed != 0);
        done   = 1;
    end
endmodule

module tb_hamming;
    wire d4, d8, d16, f4, f8, f16;
    hamming_check #(.W(4))                  c4  (.done(d4),  .failed(f4));
    hamming_check #(.W(8))                  c8  (.done(d8),  .failed(f8));
    hamming_check #(.W(16), .STRIDE(251))   c16 (.done(d16), .failed(f16));

    initial begin
        wait (d4 && d8 && d16);
        if (f4 || f8 || f16) $fatal(1, "FAIL: hamming");
        else                 $display("PASS: hamming");
        $finish;
    end
endmodule
