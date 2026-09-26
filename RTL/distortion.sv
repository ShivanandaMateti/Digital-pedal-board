// =============================================================================
// Module: distortion.sv
// Description: RTL Guitar Distortion effect with configurable drive and clipping.
// Fixed-Point: DRIVE_Q8 (256 = 1.0x gain, 384 = 1.5x, 512 = 2.0x, etc.)
//              THRESHOLD is a signed 16-bit positive integer (e.g., 12000).
// Saturated arithmetic prevents signed overflow wrap-around.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module distortion #(
    // DRIVE_Q8: Q8 fixed-point gain. 256 = 1.0x, 384 = 1.5x, 512 = 2.0x
    parameter [15:0] DRIVE_Q8  = 16'd384,
    // THRESHOLD: Symmetrical hard clipping limit (positive integer <= 32767)
    parameter [15:0] THRESHOLD = 16'd12000
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // Internal 32-bit product to prevent intermediate overflow
    // Q8 multiplication: (sample_in * DRIVE_Q8) >> 8
    wire signed [31:0] mult_result;
    wire signed [31:0] scaled_sample;

    // Treat THRESHOLD as signed for comparison
    wire signed [15:0] threshold_s;
    wire signed [31:0] threshold_32;
    wire signed [31:0] neg_threshold_32;

    assign threshold_s       = $signed(THRESHOLD);
    assign threshold_32      = {{16{threshold_s[15]}}, threshold_s};
    assign neg_threshold_32  = -threshold_32;

    assign mult_result  = $signed(sample_in) * $signed({1'b0, DRIVE_Q8});
    assign scaled_sample = mult_result >>> 8; // Arithmetic right-shift for Q8 divide

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    // Transparent bypass
                    sample_out <= sample_in;
                end else begin
                    // Hard clipping to [-THRESHOLD, +THRESHOLD]
                    if (scaled_sample > threshold_32) begin
                        sample_out <= threshold_s;
                    end else if (scaled_sample < neg_threshold_32) begin
                        sample_out <= -threshold_s;
                    end else begin
                        sample_out <= scaled_sample[15:0];
                    end
                end
            end
        end
    end

endmodule
