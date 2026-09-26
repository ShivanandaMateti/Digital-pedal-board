// =============================================================================
// Module: pedalboard_top.sv
// Description: Top-level Digital Guitar Pedalboard chaining 9 RTL audio effects.
//
// Effect Chain:
//   Input -> [0] Pitch -> [1] Wah -> [2] Distortion -> [3] Phaser
//         -> [4] Chorus -> [5] Tremolo -> [6] Delay/Echo
//         -> [7] Reverb -> [8] Looper -> Output
//
// Each module supports transparent bypass when its enable_fx bit is low.
// Valid and sample signals propagate sequentially through the pipeline.
//
// Parameters are passed from sim_config.svh via the testbench instantiation.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module pedalboard_top #(
    parameter integer PITCH_MODE     = 1,
    parameter [15:0]  DIST_DRIVE     = 16'd384,
    parameter [15:0]  DIST_THRESHOLD = 16'd12000,
    parameter integer DELAY_MS       = 250,
    parameter [15:0]  DELAY_WET      = 16'd16384,
    parameter [15:0]  DELAY_FEEDBACK = 16'd14745,
    parameter integer LOOP_MS        = 500
)(
    input  wire              clk,
    input  wire              rst,
    input  wire [8:0]        enable_fx,        // Bit per effect: [8]=Looper ... [0]=Pitch
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output wire              valid_out,
    output wire signed [15:0] sample_out
);

    // Inter-stage pipeline wires
    wire              s0_valid; wire signed [15:0] s0_sample; // Pitch out
    wire              s1_valid; wire signed [15:0] s1_sample; // Wah out
    wire              s2_valid; wire signed [15:0] s2_sample; // Distortion out
    wire              s3_valid; wire signed [15:0] s3_sample; // Phaser out
    wire              s4_valid; wire signed [15:0] s4_sample; // Chorus out
    wire              s5_valid; wire signed [15:0] s5_sample; // Tremolo out
    wire              s6_valid; wire signed [15:0] s6_sample; // Delay out
    wire              s7_valid; wire signed [15:0] s7_sample; // Reverb out
    wire              s8_valid; wire signed [15:0] s8_sample; // Looper out

    // [0] Pitch / Octave
    pitch_shift #(
        .MODE(PITCH_MODE)
    ) u_pitch (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[0]),
        .valid_in   (valid_in),
        .sample_in  (sample_in),
        .valid_out  (s0_valid),
        .sample_out (s0_sample)
    );

    // [1] Auto-Wah
    wah u_wah (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[1]),
        .valid_in   (s0_valid),
        .sample_in  (s0_sample),
        .valid_out  (s1_valid),
        .sample_out (s1_sample)
    );

    // [2] Distortion
    distortion #(
        .DRIVE_Q8  (DIST_DRIVE),
        .THRESHOLD (DIST_THRESHOLD)
    ) u_distortion (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[2]),
        .valid_in   (s1_valid),
        .sample_in  (s1_sample),
        .valid_out  (s2_valid),
        .sample_out (s2_sample)
    );

    // [3] Phaser
    phaser u_phaser (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[3]),
        .valid_in   (s2_valid),
        .sample_in  (s2_sample),
        .valid_out  (s3_valid),
        .sample_out (s3_sample)
    );

    // [4] Chorus
    chorus u_chorus (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[4]),
        .valid_in   (s3_valid),
        .sample_in  (s3_sample),
        .valid_out  (s4_valid),
        .sample_out (s4_sample)
    );

    // [5] Tremolo
    tremolo u_tremolo (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[5]),
        .valid_in   (s4_valid),
        .sample_in  (s4_sample),
        .valid_out  (s5_valid),
        .sample_out (s5_sample)
    );

    // [6] Delay / Echo
    delay_echo #(
        .DELAY_MS     (DELAY_MS),
        .WET_Q15      (DELAY_WET),
        .FEEDBACK_Q15 (DELAY_FEEDBACK)
    ) u_delay (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[6]),
        .valid_in   (s5_valid),
        .sample_in  (s5_sample),
        .valid_out  (s6_valid),
        .sample_out (s6_sample)
    );

    // [7] Reverb
    reverb u_reverb (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[7]),
        .valid_in   (s6_valid),
        .sample_in  (s6_sample),
        .valid_out  (s7_valid),
        .sample_out (s7_sample)
    );

    // [8] Looper
    looper #(
        .LOOP_MS (LOOP_MS)
    ) u_looper (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable_fx[8]),
        .valid_in   (s7_valid),
        .sample_in  (s7_sample),
        .valid_out  (s8_valid),
        .sample_out (s8_sample)
    );

    // Final outputs connect to looper output
    assign valid_out  = s8_valid;
    assign sample_out = s8_sample;

endmodule
