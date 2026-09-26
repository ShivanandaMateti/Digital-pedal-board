// =============================================================================
// Module: looper.sv
// Description: RTL Audio Looper with configurable buffer size.
//
// Automatic offline simulation mode:
//   1. Records first LOOP_MS milliseconds of audio into circular memory.
//   2. Automatically switches to repeating PLAYBACK for subsequent samples.
//
// FSM States:
//   STATE_RECORD  (0): Record incoming audio samples.
//   STATE_PLAY    (1): Replay recorded buffer in a loop.
//   STATE_OVERDUB (2): Mix new audio with existing loop (future use).
//   STATE_STOP    (3): Output silence (future use).
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module looper #(
    parameter integer MAX_LOOP_SAMPLES = 22050, // Max 500 ms buffer @ 44.1 kHz
    parameter integer LOOP_MS          = 500    // Desired loop length in milliseconds
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // Compute actual loop length in samples; clamp to [10, MAX_LOOP_SAMPLES]
    localparam integer CALC_SAMPLES = (LOOP_MS * 44100) / 1000;
    localparam integer ACTIVE_SAMPLES =
        (CALC_SAMPLES > MAX_LOOP_SAMPLES) ? MAX_LOOP_SAMPLES :
        (CALC_SAMPLES < 10)               ? 10               : CALC_SAMPLES;

    // FSM state encoding
    localparam [2:0] STATE_RECORD  = 3'd0;
    localparam [2:0] STATE_PLAY    = 3'd1;
    localparam [2:0] STATE_OVERDUB = 3'd2;
    localparam [2:0] STATE_STOP    = 3'd3;

    reg [2:0]         state;
    integer           loop_ptr;
    reg signed [15:0] loop_mem [0:MAX_LOOP_SAMPLES-1];

    reg signed [15:0] recorded_sample;
    reg signed [31:0] overdub_mix;

    always @(*) begin
        recorded_sample = loop_mem[loop_ptr];
        overdub_mix     = $signed({{16{sample_in[15]}}, sample_in})
                        + $signed({{16{recorded_sample[15]}}, recorded_sample});
    end

    integer p;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
            state      <= STATE_RECORD;
            loop_ptr   <= 0;
            for (p = 0; p < MAX_LOOP_SAMPLES; p = p + 1)
                loop_mem[p] <= 16'h0000;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    // Transparent bypass
                    sample_out <= sample_in;
                end else begin
                    case (state)
                        STATE_RECORD: begin
                            // Record incoming audio into buffer
                            loop_mem[loop_ptr] <= sample_in;
                            sample_out         <= sample_in;

                            // When buffer is full, switch to playback
                            if (loop_ptr >= ACTIVE_SAMPLES - 1) begin
                                loop_ptr <= 0;
                                state    <= STATE_PLAY;
                            end else begin
                                loop_ptr <= loop_ptr + 1;
                            end
                        end

                        STATE_PLAY: begin
                            // Play back recorded buffer continuously
                            sample_out <= recorded_sample;

                            if (loop_ptr >= ACTIVE_SAMPLES - 1)
                                loop_ptr <= 0;
                            else
                                loop_ptr <= loop_ptr + 1;
                        end

                        STATE_OVERDUB: begin
                            // Mix incoming audio with loop and write back
                            if (overdub_mix > 32'sd32767)
                                loop_mem[loop_ptr] <= 16'sh7FFF;
                            else if (overdub_mix < -32'sd32768)
                                loop_mem[loop_ptr] <= -16'sh8000;
                            else
                                loop_mem[loop_ptr] <= overdub_mix[15:0];

                            sample_out <= recorded_sample;

                            if (loop_ptr >= ACTIVE_SAMPLES - 1)
                                loop_ptr <= 0;
                            else
                                loop_ptr <= loop_ptr + 1;
                        end

                        STATE_STOP: begin
                            sample_out <= 16'h0000;
                        end

                        default: state <= STATE_RECORD;
                    endcase
                end
            end
        end
    end

endmodule
