// uart_tx -> uart_rx loopback: words, back-to-back frames, glitch rejection,
// bad stop bit, and a receiver clock that differs from the transmitter's.
`timescale 1ns/1ps
module tb_uart;
    parameter  WIDTH = 12;
    localparam CPB   = 16;
    localparam real RX_HALF = 5.0;            // RX clock half-period in ns (TX clock half-period is 5.0)

    reg clk = 0, clk_rx = 0, rst = 1, start = 0;
    reg [WIDTH-1:0] data = 0;
    wire tx, busy;

    // the RX input is the TX line, unless we force our own waveform onto it
    reg  force_en = 0, force_val = 1;
    wire rx_line = force_en ? force_val : tx;

    wire [WIDTH-1:0] data_out; wire valid, frame_error;
    integer n_valid = 0, n_ferr = 0, errors = 0;
    reg [WIDTH-1:0] last_word;

    uart_tx #(.WIDTH(WIDTH), .CLKS_PER_BIT(CPB)) u_tx
        (.clk(clk), .rst(rst), .data_in(data), .start(start), .tx(tx), .busy(busy));
    uart_rx #(.WIDTH(WIDTH), .CLKS_PER_BIT(CPB)) u_rx
        (.clk(clk_rx), .rst(rst), .rx(rx_line), .data_out(data_out), .valid(valid), .frame_error(frame_error));

    always #5         clk    = ~clk;
    always #(RX_HALF) clk_rx = ~clk_rx;

    always @(posedge clk_rx) begin
        if (valid)       begin n_valid = n_valid + 1; last_word = data_out; end
        if (frame_error) n_ferr = n_ferr + 1;
    end

    task send_and_check(input [WIDTH-1:0] word);
        integer n_before;
        begin
            n_before = n_valid;
            @(negedge clk); data = word; start = 1;
            @(negedge clk); start = 0;

            while (busy) @(negedge clk); //waits for the transmissison also waits for 4 more pulses
            repeat (4) @(negedge clk);

            if (n_valid !== n_before + 1 || last_word !== word) begin
                $display("FAIL: sent %b, valid pulses +%0d, received %b", word, n_valid - n_before, last_word);
                errors = errors + 1;
            end else begin
                $display("ok  : sent %b received %b", word, last_word);
            end
        end
    endtask

    task drive_bit(input v);                  // hold a forced level for one bit period
        begin @(negedge clk); force_val = v; repeat (CPB - 1) @(negedge clk); end
    endtask

    integer v0, f0, k;
    initial begin #20000000; $fatal(1, "TIMEOUT"); end //watchdog incase loops hang up

    initial begin
        $dumpfile("uart.vcd"); $dumpvars(0, tb_uart);
        repeat (4) @(posedge clk); rst = 0; repeat (4) @(posedge clk);

        // 1. loopback, including back-to-back frames
        send_and_check({WIDTH{1'b0}});
        send_and_check({WIDTH{1'b1}});
        send_and_check(1);
        send_and_check({1'b1, {(WIDTH-1){1'b0}}});
        send_and_check({(WIDTH/2){2'b01}});

        // 2. glitch shorter than half a bit must be ignored
        v0 = n_valid; f0 = n_ferr;
        @(negedge clk); force_en = 1; force_val = 1; @(negedge clk);
        force_val = 0; repeat (CPB/4) @(negedge clk); force_val = 1;
        repeat (4 * CPB) @(negedge clk);
        if (n_valid !== v0 || n_ferr !== f0) begin $display("FAIL: glitch was accepted as a frame"); errors = errors + 1; end
        else $display("ok  : short glitch ignored");

        // 3. stop bit low -> frame_error and no valid pulse
        v0 = n_valid; f0 = n_ferr;
        drive_bit(0);                                       // start bit
        for (k = 0; k < WIDTH; k = k + 1) drive_bit(k % 2); // some data
        drive_bit(0);                                       // BAD stop bit
        drive_bit(1); repeat (2 * CPB) @(negedge clk);
        if (n_ferr !== f0 + 1 || n_valid !== v0) begin $display("FAIL: framing error not reported correctly"); errors = errors + 1; end
        else $display("ok  : bad stop bit reported as frame_error");

        if (errors == 0) $display("PASS: uart");
        else             $fatal(1, "FAIL: uart (%0d errors)", errors);
        $finish;
    end
endmodule
