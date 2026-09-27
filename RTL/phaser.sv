// =============================================================================
// Module: phaser.sv
// Description: RTL 4-Stage All-Pass Guitar Phaser with LFO modulation.
//
// Each stage implements: y[n] = x[n-1] + a * (x[n] - y[n-1])
//
// 4 cascaded first-order all-pass sections with LFO-swept coefficient 'a'.
// Mixing the all-pass output with the dry signal creates swept notch filtering
// via phase cancellation.
//
// Fixed-Point: Q15 (32767 = 1.0)
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module phaser #(
    // All-pass coefficient range (Q15 signed)
    // A_MIN_Q15 = -20000 ~= -0.61, A_MAX_Q15 = 20000 ~= +0.61
    parameter [15:0] A_MIN_Q15    = 16'hB1E0,   // -20000 as 16-bit 2's complement
    parameter [15:0] A_MAX_Q15    = 16'd20000,   //  20000
    // LFO sweep rate: 190 ~= 0.5 Hz @ 44.1 kHz
    parameter integer LFO_STEP_24B = 190
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // LFO state
    reg [23:0]        lfo_phase;
    reg [15:0]        lfo_tri;       // unsigned 0..32767
    reg signed [15:0] a_coeff;       // current all-pass coefficient

    reg signed [31:0] coefficient_min, coefficient_max;
    reg signed [31:0] coefficient_range, coefficient_product;

    // Filter stage memory (x_prev[s] = x[n-1], y_prev[s] = y[n-1])
    reg signed [15:0] x_prev [0:3];
    reg signed [15:0] y_prev [0:3];

    // Combinational stage signals (unrolled from loop — Icarus v0.9.7 needs this)
    reg signed [15:0] stage_in_0,  stage_in_1,  stage_in_2,  stage_in_3;
    reg signed [15:0] stage_out_0, stage_out_1, stage_out_2, stage_out_3;
    reg signed [31:0] diff_0, diff_1, diff_2, diff_3;
    reg signed [31:0] amul_0, amul_1, amul_2, amul_3;
    reg signed [31:0] sout_0, sout_1, sout_2, sout_3;

    // Feedback and input saturation
    reg signed [31:0] fb_scaled;
    reg signed [31:0] in_with_fb;
    reg signed [15:0] stage0_in_sat;

    // Final output mix
    reg signed [31:0] final_mix;

    always @(*) begin
        // --- LFO: Triangle wave 0..32767 ---
        if (lfo_phase[23] == 1'b0)
            lfo_tri = {1'b0, lfo_phase[22:8]};
        else
            lfo_tri = {1'b0, ~lfo_phase[22:8]};

        // Interpolate 'a' across [A_MIN_Q15, A_MAX_Q15]
        // a = A_MIN + ((A_MAX - A_MIN) * lfo_tri) >> 15
        coefficient_min = $signed(A_MIN_Q15);
        coefficient_max = $signed(A_MAX_Q15);
        coefficient_range = coefficient_max - coefficient_min;
        coefficient_product = coefficient_range * $signed({1'b0, lfo_tri});
        a_coeff = coefficient_min + (coefficient_product >>> 15);

        // Feedback ~25% (8192 in Q15) of stage 3 output back to stage 0
        fb_scaled  = ($signed(y_prev[3]) * 32'sd8192) >>> 15;
        in_with_fb = $signed({{16{sample_in[15]}}, sample_in}) + fb_scaled;

        if (in_with_fb > 32'sd32767)       stage0_in_sat = 16'sh7FFF;
        else if (in_with_fb < -32'sd32768) stage0_in_sat = -16'sh8000;
        else                               stage0_in_sat = in_with_fb[15:0];

        // --- Stage 0: y[n] = x[n-1] + a * (x[n] - y[n-1]) ---
        stage_in_0 = stage0_in_sat;
        diff_0 = $signed({{16{stage_in_0[15]}}, stage_in_0})
                 - $signed({{16{y_prev[0][15]}}, y_prev[0]});
        amul_0 = ($signed(a_coeff) * diff_0) >>> 15;
        sout_0 = $signed({{16{x_prev[0][15]}}, x_prev[0]}) + amul_0;
        if (sout_0 > 32'sd32767)       stage_out_0 = 16'sh7FFF;
        else if (sout_0 < -32'sd32768) stage_out_0 = -16'sh8000;
        else                           stage_out_0 = sout_0[15:0];

        // --- Stage 1 ---
        stage_in_1 = stage_out_0;
        diff_1 = $signed({{16{stage_in_1[15]}}, stage_in_1})
                 - $signed({{16{y_prev[1][15]}}, y_prev[1]});
        amul_1 = ($signed(a_coeff) * diff_1) >>> 15;
        sout_1 = $signed({{16{x_prev[1][15]}}, x_prev[1]}) + amul_1;
        if (sout_1 > 32'sd32767)       stage_out_1 = 16'sh7FFF;
        else if (sout_1 < -32'sd32768) stage_out_1 = -16'sh8000;
        else                           stage_out_1 = sout_1[15:0];

        // --- Stage 2 ---
        stage_in_2 = stage_out_1;
        diff_2 = $signed({{16{stage_in_2[15]}}, stage_in_2})
                 - $signed({{16{y_prev[2][15]}}, y_prev[2]});
        amul_2 = ($signed(a_coeff) * diff_2) >>> 15;
        sout_2 = $signed({{16{x_prev[2][15]}}, x_prev[2]}) + amul_2;
        if (sout_2 > 32'sd32767)       stage_out_2 = 16'sh7FFF;
        else if (sout_2 < -32'sd32768) stage_out_2 = -16'sh8000;
        else                           stage_out_2 = sout_2[15:0];

        // --- Stage 3 ---
        stage_in_3 = stage_out_2;
        diff_3 = $signed({{16{stage_in_3[15]}}, stage_in_3})
                 - $signed({{16{y_prev[3][15]}}, y_prev[3]});
        amul_3 = ($signed(a_coeff) * diff_3) >>> 15;
        sout_3 = $signed({{16{x_prev[3][15]}}, x_prev[3]}) + amul_3;
        if (sout_3 > 32'sd32767)       stage_out_3 = 16'sh7FFF;
        else if (sout_3 < -32'sd32768) stage_out_3 = -16'sh8000;
        else                           stage_out_3 = sout_3[15:0];

        // Final wet/dry mix: 50% dry + 50% all-pass stage 3
        final_mix = ($signed({{16{sample_in[15]}}, sample_in}) >>> 1)
                  + ($signed({{16{stage_out_3[15]}}, stage_out_3}) >>> 1);
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
            lfo_phase  <= 24'd0;
            x_prev[0] <= 16'h0000; y_prev[0] <= 16'h0000;
            x_prev[1] <= 16'h0000; y_prev[1] <= 16'h0000;
            x_prev[2] <= 16'h0000; y_prev[2] <= 16'h0000;
            x_prev[3] <= 16'h0000; y_prev[3] <= 16'h0000;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    // Store all-pass state for each stage
                    x_prev[0] <= stage_in_0;  y_prev[0] <= stage_out_0;
                    x_prev[1] <= stage_in_1;  y_prev[1] <= stage_out_1;
                    x_prev[2] <= stage_in_2;  y_prev[2] <= stage_out_2;
                    x_prev[3] <= stage_in_3;  y_prev[3] <= stage_out_3;

                    // Output with saturation
                    if (final_mix > 32'sd32767)
                        sample_out <= 16'sh7FFF;
                    else if (final_mix < -32'sd32768)
                        sample_out <= -16'sh8000;
                    else
                        sample_out <= final_mix[15:0];

                    lfo_phase <= lfo_phase + LFO_STEP_24B[23:0];
                end
            end
        end
    end

endmodule
