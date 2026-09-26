// =============================================================================
// Module: delay_echo.sv
// Description:
//   RTL digital delay / echo using a circular sample buffer.
//
// Audio:
//   16-bit signed PCM, 44.1 kHz sample rate
//
// Fixed-point:
//   DRY_Q15      : Q15 gain, 32767 ~= 1.0
//   WET_Q15      : Q15 gain
//   FEEDBACK_Q15 : Q15 feedback coefficient
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module delay_echo #(
    // Maximum supported delay: 22050 samples = 500 ms @ 44.1 kHz
    parameter integer MAX_DELAY_SAMPLES = 22050,

    // Requested delay in milliseconds
    parameter integer DELAY_MS = 250,

    // Q15 gains (32767 = 1.0)
    parameter [15:0] DRY_Q15      = 16'd32767,  // ~1.0 dry level
    parameter [15:0] WET_Q15      = 16'd16384,  // ~0.5 wet level
    parameter [15:0] FEEDBACK_Q15 = 16'd14745   // ~0.45 feedback (stable)
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    // One extra location avoids read/write collision at max delay
    localparam integer BUFFER_SIZE = MAX_DELAY_SAMPLES + 1;

    // Delay in samples: clamp to valid range [1, MAX_DELAY_SAMPLES]
    localparam integer CALC_DELAY = (DELAY_MS * 44100) / 1000;
    localparam integer ACTIVE_DELAY =
        (CALC_DELAY > MAX_DELAY_SAMPLES) ? MAX_DELAY_SAMPLES :
        (CALC_DELAY < 1)                 ? 1                  : CALC_DELAY;

    // Limit feedback to prevent instability (max 28000/32768 ~= 0.854)
    // This parameter is an UNSIGNED positive Q15 gain. Clamp the full
    // encoded range, including values with bit 15 set, before multiplication.
    localparam [15:0] SAFE_FEEDBACK =
        (FEEDBACK_Q15 > 16'd28000) ? 16'd28000 : FEEDBACK_Q15;

    // =========================================================================
    // DELAY MEMORY
    // =========================================================================

    reg signed [15:0] delay_line [0:BUFFER_SIZE-1];

    integer wr_ptr;
    integer rd_ptr;
    integer samples_stored;

    // =========================================================================
    // SIGNALS
    // =========================================================================

    reg signed [15:0] delayed_sample;

    wire signed [31:0] dry_gain_32;
    wire signed [31:0] wet_gain_32;
    wire signed [31:0] feedback_gain_32;

    wire signed [63:0] dry_product;
    wire signed [63:0] wet_product;
    wire signed [63:0] feedback_product;

    wire signed [63:0] dry_scaled;
    wire signed [63:0] wet_scaled;
    wire signed [63:0] feedback_scaled;

    wire signed [63:0] mix_sum;
    wire signed [63:0] writeback_sum;

    wire signed [15:0] output_sat;
    wire signed [15:0] writeback_sat;

    // =========================================================================
    // READ POINTER (combinational)
    // =========================================================================

    always @(*) begin
        if (wr_ptr >= ACTIVE_DELAY)
            rd_ptr = wr_ptr - ACTIVE_DELAY;
        else
            rd_ptr = wr_ptr + BUFFER_SIZE - ACTIVE_DELAY;
    end

    // =========================================================================
    // DELAYED SAMPLE READ (combinational)
    // =========================================================================

    always @(*) begin
        if (samples_stored >= ACTIVE_DELAY)
            delayed_sample = delay_line[rd_ptr];
        else
            delayed_sample = 16'sh0000;
    end

    // =========================================================================
    // DSP COMBINATIONAL
    // =========================================================================

    assign dry_gain_32      = {{16{1'b0}}, DRY_Q15};      // zero-extend (positive Q15)
    assign wet_gain_32      = {{16{1'b0}}, WET_Q15};
    assign feedback_gain_32 = {{16{1'b0}}, SAFE_FEEDBACK};

    // Feedback path: delayed * feedback >> 15
    assign feedback_product = $signed({{16{delayed_sample[15]}}, delayed_sample})
                              * $signed(feedback_gain_32);
    assign feedback_scaled  = feedback_product >>> 15;

    // Write-back: input + feedback
    assign writeback_sum = $signed({{16{sample_in[15]}}, sample_in})
                           + $signed(feedback_scaled);
    assign writeback_sat = (writeback_sum > 64'sh00007FFF) ? 16'sh7FFF :
                           (writeback_sum < -64'sh00008000) ? -16'sh8000 :
                            writeback_sum[15:0];

    // Dry/wet mix
    assign dry_product = $signed({{16{sample_in[15]}}, sample_in}) * $signed(dry_gain_32);
    assign wet_product = $signed({{16{delayed_sample[15]}}, delayed_sample}) * $signed(wet_gain_32);
    assign dry_scaled  = dry_product >>> 15;
    assign wet_scaled  = wet_product >>> 15;
    assign mix_sum     = $signed(dry_scaled) + $signed(wet_scaled);
    assign output_sat  = (mix_sum > 64'sh00007FFF) ? 16'sh7FFF :
                         (mix_sum < -64'sh00008000) ? -16'sh8000 :
                          mix_sum[15:0];

    // =========================================================================
    // SEQUENTIAL LOGIC
    // =========================================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out      <= 1'b0;
            sample_out     <= 16'sh0000;
            wr_ptr         <= 0;
            samples_stored <= 0;
        end else begin
            valid_out <= valid_in;

            if (valid_in) begin
                if (!enable) begin
                    // Transparent bypass
                    sample_out <= sample_in;
                end else begin
                    // Write input + feedback into delay line
                    delay_line[wr_ptr] <= writeback_sat;

                    // Output dry + wet delayed
                    sample_out <= output_sat;

                    // Advance circular write pointer
                    if (wr_ptr == BUFFER_SIZE - 1)
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;

                    // Count stored samples up to ACTIVE_DELAY
                    if (samples_stored < ACTIVE_DELAY)
                        samples_stored <= samples_stored + 1;
                end
            end
        end
    end

endmodule