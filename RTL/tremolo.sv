// =============================================================================
// Module: tremolo.sv
// Description: RTL Tremolo effect (LFO-driven Amplitude Modulation).
// Equation: y[n] = (x[n] * gain[n]) >>> 15
// Fixed-Point: Q15 arithmetic throughout (32767 = 1.0).
//
// LFO generates a triangle wave sweeping from 0 to 32767.
// Gain oscillates between (1 - DEPTH) and 1.0, producing amplitude modulation.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module tremolo #(
    // DEPTH_Q15: Modulation depth in Q15. 24576 = 0.75 (75% depth)
    parameter [15:0] DEPTH_Q15    = 16'd24576,
    // LFO_STEP_24B: Phase increment per sample. 1522 ~= 4.0 Hz @ 44.1 kHz
    parameter integer LFO_STEP_24B = 1522
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // 24-bit phase accumulator
    reg [23:0]      lfo_phase;
    reg [15:0]      lfo_tri;      // unsigned 0..32767
    reg signed [31:0] mod_prod;
    reg signed [15:0] gain_q15;
    reg signed [31:0] sample_prod;

    always @(*) begin
        // Triangle wave oscillating from 0 to 32767
        // Upper half of phase (bit 23 = 1) inverts to create downslope
        if (lfo_phase[23] == 1'b0)
            lfo_tri = {1'b0, lfo_phase[22:8]};   // 0 to 32767
        else
            lfo_tri = {1'b0, ~lfo_phase[22:8]};  // 32767 to 0

        // Attenuated depth: (DEPTH_Q15 * lfo_tri) >>> 15
        mod_prod   = $signed({1'b0, DEPTH_Q15}) * $signed({1'b0, lfo_tri});
        // gain_q15 swings between (32767 - DEPTH_Q15) and 32767
        gain_q15   = 16'sd32767 - $signed(mod_prod >>> 15);

        // Amplitude modulation: sample_in * gain_q15
        sample_prod = $signed(sample_in) * $signed(gain_q15);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
            lfo_phase  <= 24'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    // Q15 output: result / 32768
                    sample_out <= sample_prod[30:15];
                    // Advance LFO phase
                    lfo_phase  <= lfo_phase + LFO_STEP_24B[23:0];
                end
            end
        end
    end

endmodule
