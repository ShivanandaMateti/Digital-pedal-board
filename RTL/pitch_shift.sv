// =============================================================================
// Module: pitch_shift.sv
// Description: RTL Guitar-Pedal-Style Octave Effect (Hardware Emulation).
//
// Modes:
//   MODE = 1: Octave-Up (Full-Wave Rectifier + DC-Blocking Highpass).
//             Emulates classic analog octave pedals (Octavia / Green Ringer)
//             which fold the waveform to double the fundamental frequency.
//   MODE = 2: Octave-Down (Zero-Crossing Subharmonic Flip-Flop Divider).
//             Emulates classic analog sub-octave dividers (BOSS OC-2 style)
//             which toggle a sub-octave polarity once per input cycle.
//
// NOTE: This models synthesizable hardware guitar pedal circuits. It is NOT
//       an arbitrary-semitone studio FFT phase-vocoder pitch shifter.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module pitch_shift #(
    parameter integer MODE = 1  // 1: Octave Up, 2: Octave Down
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // MODE 1: Octave Up — Full-wave rectifier + DC blocker
    reg signed [15:0] abs_sample;   // |sample_in|
    reg signed [15:0] rect_prev;    // previous absolute sample
    reg signed [15:0] dc_prev;      // previous DC-blocker output
    reg signed [31:0] dc_mult;      // 0.992 * dc_prev (Q15: 32500/32768)
    reg signed [31:0] hp_calc;      // highpass output (before clamp)
    reg signed [15:0] oct_up_out;   // final octave-up output sample

    // MODE 2: Octave Down — Zero-crossing flip-flop divider
    reg signed [15:0] prev_sample;  // previous sample for edge detection
    reg crossing_armed;
    reg next_polarity;
    reg               sub_polarity; // T flip-flop: 0=normal, 1=inverted
    reg signed [15:0] oct_down_out; // final octave-down output sample

    // Combinational calculations
    always @(*) begin
        // === MODE 1: Full-wave rectification ===
        // Prevent negation overflow at -32768 (minimum int16)
        if (sample_in == -16'sh8000)
            abs_sample = 16'sh7FFF;
        else if ($signed(sample_in) < 0)
            abs_sample = -sample_in;
        else
            abs_sample = sample_in;

        // DC-blocker: y[n] = x[n] - x[n-1] + 0.992 * y[n-1]
        // 0.992 in Q15 ~= 32500
        dc_mult = ($signed(dc_prev) * 32'sd32500) >>> 15;
        hp_calc = ($signed({{16{abs_sample[15]}}, abs_sample})
                 - $signed({{16{rect_prev[15]}}, rect_prev}))
                 + dc_mult;

        if (hp_calc > 32'sd32767)       oct_up_out = 16'sh7FFF;
        else if (hp_calc < -32'sd32768) oct_up_out = -16'sh8000;
        else                            oct_up_out = hp_calc[15:0];

        // Schmitt state remembers the negative threshold crossing until
        // the positive threshold is reached; gradual crossings are not lost.
        next_polarity = sub_polarity;
        if (crossing_armed && $signed(sample_in) >= 16'sd200)
            next_polarity = ~sub_polarity;
        // Rectified envelope with a polarity that flips once per input cycle.
        // This is a monophonic sub-octave pedal, not a transparent pitch shifter.
        oct_down_out = next_polarity ? abs_sample : -abs_sample;
    end

    // Sequential process
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out    <= 1'b0;
            sample_out   <= 16'h0000;
            rect_prev    <= 16'h0000;
            dc_prev      <= 16'h0000;
            prev_sample  <= 16'h0000;
            sub_polarity <= 1'b0;
            crossing_armed <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    if (MODE == 1) begin
                        // Octave-up: output rectified & high-passed
                        sample_out <= oct_up_out;
                        rect_prev  <= abs_sample;
                        dc_prev    <= oct_up_out;
                    end else begin
                        // Octave-down: output polarity-toggled signal
                        sample_out <= oct_down_out;

                        if ($signed(sample_in) <= -16'sd200)
                            crossing_armed <= 1'b1;
                        else if (crossing_armed && $signed(sample_in) >= 16'sd200)
                            crossing_armed <= 1'b0;
                        sub_polarity <= next_polarity;

                        prev_sample <= sample_in;
                    end
                end
            end
        end
    end

endmodule
