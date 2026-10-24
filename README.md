# Hamming-coded UART link

A serial link written in Verilog that survives single-bit errors on the wire. Data is encoded with a Hamming code, sent over a UART, and decoded at the other end. If one bit of the transmitted frame gets flipped in transit, the receiver finds it and repairs it.

This is a simulation project, meant to show how RTL for a small communication system is built and verified from the ground up: parameterized modules, a clocked serial protocol, and exhaustive self-checking testbenches.

## How it works

```
data --> hamming_enc --> uart_tx --> [ noisy line ] --> uart_rx --> hamming_dec --> data
                                                                          |
                                                                      is_error
```

**Hamming code** (`hamming_enc.v`, `hamming_dec.v`). The encoder is purely combinational. It places the data bits at the non-power-of-two positions of the codeword and computes each parity bit as the XOR of every position whose index has that parity bit's binary digit set. 8 data bits become a 12-bit codeword. The decoder recomputes the same XORs over the received word, including the parity bits. The result, the syndrome, is the position of a flipped bit in binary, or zero when nothing is wrong. The decoder flips that bit back, extracts the data, and raises `is_error` if the syndrome was non-zero. The data width is a parameter (`DATA_LEN`, a power of two, 4 or larger).

**UART** (`uart_tx.v`, `uart_rx.v`). One frame is a start bit (low), the data bits LSB first, and a stop bit (high), with no parity bit. The word width is a parameter, so it carries the 12-bit Hamming codeword. The bit period is `CLKS_PER_BIT` cycles of the system clock, derived from `CLK_FREQ` and `BAUD`. Both modules are four-state machines (idle, start, data, stop). The receiver passes the line through a two-flop synchronizer, confirms the start bit again half a bit later (so glitches are ignored), samples every bit in its middle, and reports `frame_error` if the stop bit is not high.

## What is tested

All testbenches are self-checking and finish with `PASS` or a failure message. 

- `tb_hamming.v` tests the encoder and decoder alone, with no clock. For 4, 8 and 16 data bits it checks every data word with no error, and with every possible single-bit flip, including flips of the parity bits themselves. It also flips every pair of bits (sampled for 16 bits) and counts the outcomes.
- `tb_uart.v` sends words from `uart_tx` to `uart_rx`, including back-to-back frames. It checks that a short glitch on the line is ignored, that a bad stop bit is reported, and that data is still received with the receiver clock a little off from the transmitter's.
- `tb_link.v` tests the whole chain, with `channel.v` flipping bits on the serial line. For 8 data bits it sends all 256 words with no error, then all 256 words with each of the 12 codeword bits flipped on the wire (3,072 frames), and compares the received word and `is_error` against what was sent. It also tests double-bit errors on a few words and a corrupted stop bit.

## Limitations

- A plain Hamming code corrects any single-bit error but cannot tell a double-bit error from a single one. A double-bit error is detected in the sense that `is_error` goes high, but the decoder then "corrects" the wrong bit, so the output is usually wrong. In the tests, every double-bit error at 4 and 8 data bits came back with wrong data. At 16 data bits a few came back correct only by coincidence, when both flipped bits were parity bits. Telling the two cases apart would need an extra overall parity bit (SECDED), which this project does not include.
- The UART has no parity bit and a single stop bit.
- This has only been run in simulation (Icarus Verilog), with a small `CLKS_PER_BIT` of 16 for readable runs. It has not been put on hardware.
- The encoder and decoder have been tested at 4, 8 and 16 data bits.