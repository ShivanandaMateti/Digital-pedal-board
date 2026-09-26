// =============================================================================
// Module: chorus.sv
// Description: RTL Digital Chorus using an LFO-modulated short circular delay line.
// Fixed-Point: Q15 wet/dry mixing.
// Modulates read address with a smooth triangle LFO (~1.5 Hz) around a base delay.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module chorus #(
    parameter integer BUFFER_SIZE  = 1024,  // Max ~23 ms @ 44.1 kHz
    parameter integer BASE_DELAY   = 350,   // ~8 ms base delay in samples
    parameter integer MOD_DEPTH    = 100,   // +/- ~2.2 ms modulation depth in samples
    parameter integer LFO_STEP_24B = 570    // ~1.5 Hz LFO rate @ 44.1 kHz
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // Circular delay buffer
    reg signed [15:0] delay_buf [0:BUFFER_SIZE-1];
    integer wr_ptr;
    integer rd_ptr, rd_ptr_older;
    integer delay_q8, frac_q8;
    reg signed [31:0] wet_interp;

    // 24-bit phase accumulator for LFO
    reg [23:0] lfo_phase;
    reg [15:0] lfo_tri;
    integer    mod_samples;
    integer    total_delay;

    // DSP intermediate signals
    reg signed [15:0] wet_sample;
    reg signed [31:0] mixed_32;

    // Triangle wave generator from phase accumulator
    always @(*) begin
        // Q15 triangle, centered modulation, and 8 fractional delay bits.
        if (lfo_phase[23] == 1'b0)
            lfo_tri = {1'b0, lfo_phase[22:8]};
        else
            lfo_tri = {1'b0, ~lfo_phase[22:8]};
        delay_q8 = (BASE_DELAY - MOD_DEPTH) * 256
                 + ((lfo_tri * (2 * MOD_DEPTH * 256)) >> 15);
        if (delay_q8 > (BUFFER_SIZE - 2)*256)
            delay_q8 = (BUFFER_SIZE - 2)*256;
        else if (delay_q8 < 256)
            delay_q8 = 256;
        total_delay = delay_q8 >> 8;
        frac_q8 = delay_q8 & 255;
        mod_samples = total_delay - BASE_DELAY;

        // Calculate circular read pointer
        if (wr_ptr >= total_delay)
            rd_ptr = wr_ptr - total_delay;
        else
            rd_ptr = wr_ptr + BUFFER_SIZE - total_delay;

        // Read wet sample and compute 50/50 mix
        rd_ptr_older = (rd_ptr == 0) ? BUFFER_SIZE - 1 : rd_ptr - 1;
        wet_interp = $signed(delay_buf[rd_ptr]) * (256 - frac_q8)
                   + $signed(delay_buf[rd_ptr_older]) * frac_q8;
        wet_sample = wet_interp >>> 8;
        // 50% Dry + 50% Wet: arithmetic shift right by 1 = divide by 2
        mixed_32 = ($signed(sample_in) >>> 1) + ($signed(wet_sample) >>> 1);
    end

    // Sequential process
    integer j;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            sample_out <= 16'h0000;
            wr_ptr    <= 0;
            lfo_phase <= 24'd0;
            for (j = 0; j < BUFFER_SIZE; j = j + 1) begin
                delay_buf[j] <= 16'h0000;
            end
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    // Write current sample into circular buffer
                    delay_buf[wr_ptr] <= sample_in;

                    // Output saturated mix
                    if (mixed_32 > 32'sd32767)
                        sample_out <= 16'sh7FFF;
                    else if (mixed_32 < -32'sd32768)
                        sample_out <= -16'sh8000;
                    else
                        sample_out <= mixed_32[15:0];

                    // Advance buffer write pointer
                    if (wr_ptr >= BUFFER_SIZE - 1)
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;

                    // Advance LFO phase accumulator
                    lfo_phase <= lfo_phase + LFO_STEP_24B[23:0];
                end
            end
        end
    end

endmodule
