// =============================================================================
// Module: wah.sv
// Description: RTL Auto-Wah using an LFO-swept Chamberlin State Variable Filter.
// Fixed-Point: Q15 fixed-point arithmetic for frequency and resonance controls.
// Sweeps a resonant bandpass filter across guitar vocal frequencies (400 Hz - 2.2 kHz).
//
// Chamberlin SVF equations:
//   lp[n] = lp[n-1] + f * bp[n-1]
//   hp[n] = in[n]   - lp[n] - q * bp[n-1]
//   bp[n] = bp[n-1] + f * hp[n]
//
// Output = 40% dry + 60% bandpass (wah coloration)
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module wah #(
    // F_MIN_Q15: minimum filter tuning (Q15). 1800 ~= 380 Hz
    parameter [15:0] F_MIN_Q15    = 16'd1800,
    // F_MAX_Q15: maximum filter tuning (Q15). 10000 ~= 2.2 kHz
    parameter [15:0] F_MAX_Q15    = 16'd10000,
    // Q_DAMP_Q15: damping coefficient (Q15). 4915 ~= 0.15 (resonant Q ~6.6)
    parameter [15:0] Q_DAMP_Q15   = 16'd4915,
    // LFO_STEP_24B: 570 ~= 1.5 Hz sweep rate @ 44.1 kHz
    parameter integer LFO_STEP_24B = 570
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
    reg [15:0]      lfo_tri;         // unsigned 0..32767
    reg signed [15:0] f_coeff;       // current filter tuning coefficient

    reg signed [31:0] tuning_range, tuning_product;

    // Filter state registers
    reg signed [15:0] lowpass;
    reg signed [15:0] bandpass;

    // Combinational arithmetic signals
    reg signed [31:0] f_mult_bp;
    reg signed [31:0] q_mult_bp;
    reg signed [31:0] f_mult_hp;
    reg signed [31:0] next_lp;
    reg signed [31:0] highpass;
    reg signed [31:0] next_bp;
    reg signed [31:0] mixed_out;
    reg signed [15:0] sat_lp;
    reg signed [15:0] sat_bp;

    // Saturate helper: 32-bit to 16-bit
    // (used inline as assignments below)

    always @(*) begin
        // --- LFO: Triangle wave 0..32767 ---
        if (lfo_phase[23] == 1'b0)
            lfo_tri = {1'b0, lfo_phase[22:8]};
        else
            lfo_tri = {1'b0, ~lfo_phase[22:8]};

        // Interpolate f between F_MIN and F_MAX
        // f_coeff = F_MIN + ((F_MAX - F_MIN) * lfo_tri) >> 15
        // Widen BEFORE multiplying: the product needs up to 29 bits.
        tuning_range = $signed({1'b0, F_MAX_Q15}) - $signed({1'b0, F_MIN_Q15});
        tuning_product = tuning_range * $signed({1'b0, lfo_tri});
        f_coeff = $signed({1'b0, F_MIN_Q15}) + (tuning_product >>> 15);

        // --- Chamberlin SVF ---
        // lp[n] = lp[n-1] + f * bp[n-1]
        f_mult_bp = ($signed(f_coeff) * $signed(bandpass)) >>> 15;
        next_lp   = $signed({{16{lowpass[15]}}, lowpass}) + f_mult_bp;

        // Saturate lowpass
        if (next_lp > 32'sd32767)       sat_lp = 16'sh7FFF;
        else if (next_lp < -32'sd32768) sat_lp = -16'sh8000;
        else                            sat_lp = next_lp[15:0];

        // hp[n] = in[n] - lp[n] - q * bp[n-1]
        q_mult_bp = ($signed({1'b0, Q_DAMP_Q15}) * $signed(bandpass)) >>> 15;
        highpass  = $signed({{16{sample_in[15]}}, sample_in})
                    - $signed({{16{sat_lp[15]}}, sat_lp})
                    - q_mult_bp;

        // bp[n] = bp[n-1] + f * hp[n]
        f_mult_hp = ($signed(f_coeff) * highpass) >>> 15;
        next_bp   = $signed({{16{bandpass[15]}}, bandpass}) + f_mult_hp;

        // Saturate bandpass
        if (next_bp > 32'sd32767)       sat_bp = 16'sh7FFF;
        else if (next_bp < -32'sd32768) sat_bp = -16'sh8000;
        else                            sat_bp = next_bp[15:0];

        // Output mix: 40% dry + 60% bandpass
        // 13107/32768 ~= 0.40,  19660/32768 ~= 0.60
        mixed_out = (($signed({{16{sample_in[15]}}, sample_in}) * 32'sd13107) >>> 15)
                  + (($signed({{16{sat_bp[15]}}, sat_bp}) * 32'sd19660) >>> 15);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
            lowpass    <= 16'h0000;
            bandpass   <= 16'h0000;
            lfo_phase  <= 24'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    // Update filter states
                    lowpass  <= sat_lp;
                    bandpass <= sat_bp;

                    // Output with saturation
                    if (mixed_out > 32'sd32767)
                        sample_out <= 16'sh7FFF;
                    else if (mixed_out < -32'sd32768)
                        sample_out <= -16'sh8000;
                    else
                        sample_out <= mixed_out[15:0];

                    // Advance LFO
                    lfo_phase <= lfo_phase + LFO_STEP_24B[23:0];
                end
            end
        end
    end

endmodule
