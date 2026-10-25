// End-to-end: hamming_enc -> uart_tx -> channel (corrupts the serial line) -> uart_rx -> hamming_dec.
// The testbench holds 'data' stable for the whole frame, as the encoder output feeds uart_tx directly.
//   1. no error, all words          : same data out, is_error = 0
//   2. every single-bit line error  : same data out, is_error = 1   (all 12 slots incl. parity bits)
//   3. double errors (sampled words): is_error = 1, wrong data counted (plain Hamming limitation)
//   4. corrupted stop bit           : receiver reports frame_error, nothing is decoded
`timescale 1ns/1ps
module tb_link;
    parameter  DATA_LEN = 8;
    localparam PARITIES = $clog2(DATA_LEN) + 1;
    localparam CODE_LEN = DATA_LEN + PARITIES;
    localparam CPB      = 16;

    reg clk = 0, rst = 1, start = 0;
    reg  [DATA_LEN-1:0] data = 0;
    reg  [CODE_LEN-1:0] flip_mask = 0;
    reg                 flip_stop = 0;

    wire tx, busy, line;
    wire [DATA_LEN-1:0] data_out;
    wire is_error, valid, frame_error;

    wire [CODE_LEN-1:0] code_tx, code_rx;

    hamming_enc #(.DATA_LEN(DATA_LEN)) u_enc (
        .data_in(data), .code_out(code_tx));

    uart_tx #(.WIDTH(CODE_LEN), .CLKS_PER_BIT(CPB)) u_tx (
        .clk(clk), .rst(rst), .data_in(code_tx), .start(start), .tx(tx), .busy(busy));

    channel #(.CODE_LEN(CODE_LEN), .CLKS_PER_BIT(CPB)) u_ch (
        .clk(clk), .rst(rst), .tx_in(tx), .flip_mask(flip_mask), .flip_stop(flip_stop), .rx_out(line));

    uart_rx #(.WIDTH(CODE_LEN), .CLKS_PER_BIT(CPB)) u_rx (
        .clk(clk), .rst(rst), .rx(line),
        .data_out(code_rx), .valid(valid), .frame_error(frame_error));

    hamming_dec #(.DATA_LEN(DATA_LEN)) u_dec (
        .code_in(code_rx), .data_out(data_out), .is_error(is_error));

    always #5 clk = ~clk;
    initial begin #2000000000; $fatal(1, "TIMEOUT"); end

    // capture what the receiver reports for the current frame
    reg                 got_valid, got_ferr, got_err;
    reg [DATA_LEN-1:0]  got_data;
    always @(posedge clk) begin
        if (valid)       begin got_valid = 1; got_data = data_out; got_err = is_error; end
        if (frame_error) got_ferr = 1;
    end

    task run_frame(input [DATA_LEN-1:0] word, input [CODE_LEN-1:0] mask, input fstop);
        begin
            got_valid = 0; got_ferr = 0; got_err = 0; got_data = 0;
            flip_mask = mask; flip_stop = fstop;
            @(negedge clk); data = word; start = 1;
            @(negedge clk); start = 0;
            while (busy) @(negedge clk);
            repeat (4) @(negedge clk);
        end
    endtask

    integer w, a, b, i;
    integer n0 = 0, n0_bad = 0, n1 = 0, n1_bad = 0, n2 = 0, n2_missed = 0, n2_wrong = 0, n3 = 0, n3_bad = 0;
    reg [DATA_LEN-1:0] sample [0:3];

    initial begin
        $dumpfile("link.vcd"); $dumpvars(0, tb_link);
        sample[0] = 8'h00; sample[1] = 8'hFF; sample[2] = 8'hA5; sample[3] = 8'h3C;
        repeat (4) @(posedge clk); rst = 0; repeat (4) @(posedge clk);

        // two frames worth looking at in GTKWave: a clean one, then one with a flipped bit
        run_frame(8'hA5, 0, 0);
        run_frame(8'hA5, 12'h010, 0);
        $dumpoff;                                           // keep the sweeps out of the waveform file

        for (w = 0; w < (1 << DATA_LEN); w = w + 1) begin   // 1. no errors
            run_frame(w, 0, 0); n0 = n0 + 1;
            if (!got_valid || got_data !== w || got_err) n0_bad = n0_bad + 1;
        end

        for (w = 0; w < (1 << DATA_LEN); w = w + 1)         // 2. every single-bit error
            for (a = 0; a < CODE_LEN; a = a + 1) begin
                run_frame(w, 1 << a, 0); n1 = n1 + 1;
                if (!got_valid || got_data !== w || !got_err) n1_bad = n1_bad + 1;
            end

        for (i = 0; i < 4; i = i + 1)                       // 3. double errors on sampled words
            for (a = 0; a < CODE_LEN; a = a + 1)
                for (b = a + 1; b < CODE_LEN; b = b + 1) begin
                    run_frame(sample[i], (1 << a) | (1 << b), 0); n2 = n2 + 1;
                    if (!got_valid || !got_err) n2_missed = n2_missed + 1;
                    if (got_data !== sample[i]) n2_wrong = n2_wrong + 1;
                end

        for (i = 0; i < 4; i = i + 1) begin                 // 4. stop bit corrupted
            run_frame(sample[i], 0, 1); n3 = n3 + 1;
            if (got_valid || !got_ferr) n3_bad = n3_bad + 1;
        end

        $display("[end-to-end link, %0d data bits -> %0d-bit codeword]", DATA_LEN, CODE_LEN);
        $display("   no error   : %0d frames, %0d failures", n0, n0_bad);
        $display("   1-bit error: %0d frames, %0d failures (all corrected, all flagged)", n1, n1_bad);
        $display("   2-bit error: %0d frames, %0d not flagged, %0d returned wrong data (plain Hamming cannot fix these)",
                 n2, n2_missed, n2_wrong);
        $display("   bad stop   : %0d frames, %0d failures (frame_error expected)", n3, n3_bad);
        if (n0_bad || n1_bad || n2_missed || n3_bad) $fatal(1, "FAIL: link");
        else $display("PASS: link");
        $finish;
    end
endmodule
