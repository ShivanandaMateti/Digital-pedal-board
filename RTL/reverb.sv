// =============================================================================
// Module: reverb.sv
// Description: RTL Digital Reverb using 4 Parallel Feedback Comb Filters
//              and 2 Cascaded All-Pass Diffusion Stages (Schroeder Architecture).
// Fixed-Point: Q15 arithmetic (32767 = 1.0).
// Memory bounded: Total RAM footprint < 6K samples (~11.5 KB), highly synthesizable.
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module reverb #(
    parameter [15:0] DRY_Q15      = 16'd24576, // 0.75 dry  (Q15: 24576/32768)
    parameter [15:0] WET_Q15      = 16'd16384, // 0.50 wet
    parameter [15:0] FEEDBACK_Q15 = 16'd23000  // ~0.70 decay
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              enable,
    input  wire              valid_in,
    input  wire signed [15:0] sample_in,
    output reg               valid_out,
    output reg  signed [15:0] sample_out
);

    // Comb filter delay lengths (distinct; not pairwise coprime)
    localparam integer C1_LEN  = 1116;
    localparam integer C2_LEN  = 1188;
    localparam integer C3_LEN  = 1277;
    localparam integer C4_LEN  = 1356;

    // All-pass diffusion delay lengths
    localparam integer AP1_LEN = 225;
    localparam integer AP2_LEN = 556;

    // Safety feedback clamp: max ~0.823 to prevent instability
    localparam [15:0] SAFE_FB = ($signed(FEEDBACK_Q15) > 16'sd27000) ? 16'd27000 :
                                ($signed(FEEDBACK_Q15) < 16'sd0)     ? 16'd0     :
                                                                        FEEDBACK_Q15;

    // Comb filter memories
    reg signed [15:0] c1_mem [0:C1_LEN-1];
    reg signed [15:0] c2_mem [0:C2_LEN-1];
    reg signed [15:0] c3_mem [0:C3_LEN-1];
    reg signed [15:0] c4_mem [0:C4_LEN-1];

    integer c1_ptr, c2_ptr, c3_ptr, c4_ptr;

    // All-pass memories
    reg signed [15:0] ap1_mem [0:AP1_LEN-1];
    reg signed [15:0] ap2_mem [0:AP2_LEN-1];

    integer ap1_ptr, ap2_ptr;

    // Comb filter signals
    reg signed [15:0] c1_out, c2_out, c3_out, c4_out;
    reg signed [31:0] c1_fb,  c2_fb,  c3_fb,  c4_fb;
    reg signed [31:0] c1_sum, c2_sum, c3_sum, c4_sum;
    reg signed [15:0] c1_in,  c2_in,  c3_in,  c4_in;

    // Comb average
    reg signed [31:0] comb_sum;
    reg signed [15:0] comb_scaled;

    // All-pass 1 signals (coefficient g = 0.5)
    reg signed [15:0] ap1_del;
    reg signed [31:0] ap1_out32;
    reg signed [15:0] ap1_out;
    reg signed [31:0] ap1_in_sum;
    reg signed [15:0] ap1_in_sat;

    // All-pass 2 signals (coefficient g = 0.5)
    reg signed [15:0] ap2_del;
    reg signed [31:0] ap2_out32;
    reg signed [15:0] ap2_out;
    reg signed [31:0] ap2_in_sum;
    reg signed [15:0] ap2_in_sat;

    // Wet/dry mix
    reg signed [31:0] dry_scaled;
    reg signed [31:0] wet_scaled;
    reg signed [31:0] total_mix;

    always @(*) begin
        // Read comb delay line outputs at current pointers
        c1_out = c1_mem[c1_ptr];
        c2_out = c2_mem[c2_ptr];
        c3_out = c3_mem[c3_ptr];
        c4_out = c4_mem[c4_ptr];

        // Comb feedback: delayed * feedback >> 15 (Q15 multiply)
        c1_fb = ($signed(c1_out) * $signed({1'b0, SAFE_FB})) >>> 15;
        c2_fb = ($signed(c2_out) * $signed({1'b0, SAFE_FB})) >>> 15;
        c3_fb = ($signed(c3_out) * $signed({1'b0, SAFE_FB})) >>> 15;
        c4_fb = ($signed(c4_out) * $signed({1'b0, SAFE_FB})) >>> 15;

        // Comb inputs = input + feedback (with saturation)
        c1_sum = $signed({{16{sample_in[15]}}, sample_in}) + c1_fb;
        c2_sum = $signed({{16{sample_in[15]}}, sample_in}) + c2_fb;
        c3_sum = $signed({{16{sample_in[15]}}, sample_in}) + c3_fb;
        c4_sum = $signed({{16{sample_in[15]}}, sample_in}) + c4_fb;

        c1_in = (c1_sum > 32'sd32767) ? 16'sh7FFF : (c1_sum < -32'sd32768) ? -16'sh8000 : c1_sum[15:0];
        c2_in = (c2_sum > 32'sd32767) ? 16'sh7FFF : (c2_sum < -32'sd32768) ? -16'sh8000 : c2_sum[15:0];
        c3_in = (c3_sum > 32'sd32767) ? 16'sh7FFF : (c3_sum < -32'sd32768) ? -16'sh8000 : c3_sum[15:0];
        c4_in = (c4_sum > 32'sd32767) ? 16'sh7FFF : (c4_sum < -32'sd32768) ? -16'sh8000 : c4_sum[15:0];

        // Average 4 comb outputs (divide by 4 = shift right 2)
        comb_sum = ($signed(c1_out) >>> 2) + ($signed(c2_out) >>> 2)
                 + ($signed(c3_out) >>> 2) + ($signed(c4_out) >>> 2);
        comb_scaled = (comb_sum > 32'sd32767) ? 16'sh7FFF :
                      (comb_sum < -32'sd32768) ? -16'sh8000 : comb_sum[15:0];

        // True Schroeder all-pass, g=0.5:
        // y[n] = d[n] - g*x[n]; buffer_write = x[n] + g*y[n].
        // H(z) = (z^-M - g)/(1 - g*z^-M), before quantization/clipping.
        ap1_del = ap1_mem[ap1_ptr];
        ap1_out32 = $signed({{16{ap1_del[15]}}, ap1_del})
                    - ($signed({{16{comb_scaled[15]}}, comb_scaled}) >>> 1);
        ap1_out = (ap1_out32 > 32767) ? 16'sh7fff :
                  (ap1_out32 < -32768) ? 16'sh8000 : ap1_out32[15:0];
        ap1_in_sum = $signed({{16{comb_scaled[15]}}, comb_scaled})
                     + ($signed({{16{ap1_out[15]}}, ap1_out}) >>> 1);
        ap1_in_sat = (ap1_in_sum > 32767) ? 16'sh7fff :
                     (ap1_in_sum < -32768) ? 16'sh8000 : ap1_in_sum[15:0];

        ap2_del = ap2_mem[ap2_ptr];
        ap2_out32 = $signed({{16{ap2_del[15]}}, ap2_del})
                    - ($signed({{16{ap1_out[15]}}, ap1_out}) >>> 1);
        ap2_out = (ap2_out32 > 32767) ? 16'sh7fff :
                  (ap2_out32 < -32768) ? 16'sh8000 : ap2_out32[15:0];
        ap2_in_sum = $signed({{16{ap1_out[15]}}, ap1_out})
                     + ($signed({{16{ap2_out[15]}}, ap2_out}) >>> 1);
        ap2_in_sat = (ap2_in_sum > 32767) ? 16'sh7fff :
                     (ap2_in_sum < -32768) ? 16'sh8000 : ap2_in_sum[15:0];

        // Final wet/dry mix (Q15 multiply)
        dry_scaled = ($signed({{16{sample_in[15]}}, sample_in}) * $signed({1'b0, DRY_Q15})) >>> 15;
        wet_scaled = ($signed({{16{ap2_out[15]}}, ap2_out}) * $signed({1'b0, WET_Q15}))    >>> 15;
        total_mix  = dry_scaled + wet_scaled;
    end

    integer n;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out  <= 1'b0;
            sample_out <= 16'h0000;
            c1_ptr     <= 0;
            c2_ptr     <= 0;
            c3_ptr     <= 0;
            c4_ptr     <= 0;
            ap1_ptr    <= 0;
            ap2_ptr    <= 0;
            for (n = 0; n < C1_LEN;  n = n + 1) c1_mem[n]  <= 16'h0000;
            for (n = 0; n < C2_LEN;  n = n + 1) c2_mem[n]  <= 16'h0000;
            for (n = 0; n < C3_LEN;  n = n + 1) c3_mem[n]  <= 16'h0000;
            for (n = 0; n < C4_LEN;  n = n + 1) c4_mem[n]  <= 16'h0000;
            for (n = 0; n < AP1_LEN; n = n + 1) ap1_mem[n] <= 16'h0000;
            for (n = 0; n < AP2_LEN; n = n + 1) ap2_mem[n] <= 16'h0000;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (!enable) begin
                    sample_out <= sample_in;
                end else begin
                    // Write back comb memories
                    c1_mem[c1_ptr] <= c1_in;
                    c2_mem[c2_ptr] <= c2_in;
                    c3_mem[c3_ptr] <= c3_in;
                    c4_mem[c4_ptr] <= c4_in;

                    // Write back all-pass memories
                    ap1_mem[ap1_ptr] <= ap1_in_sat;
                    ap2_mem[ap2_ptr] <= ap2_in_sat;

                    // Output with saturation
                    if (total_mix > 32'sd32767)      sample_out <= 16'sh7FFF;
                    else if (total_mix < -32'sd32768) sample_out <= -16'sh8000;
                    else                              sample_out <= total_mix[15:0];

                    // Advance circular pointers
                    c1_ptr  <= (c1_ptr  >= C1_LEN  - 1) ? 0 : (c1_ptr  + 1);
                    c2_ptr  <= (c2_ptr  >= C2_LEN  - 1) ? 0 : (c2_ptr  + 1);
                    c3_ptr  <= (c3_ptr  >= C3_LEN  - 1) ? 0 : (c3_ptr  + 1);
                    c4_ptr  <= (c4_ptr  >= C4_LEN  - 1) ? 0 : (c4_ptr  + 1);
                    ap1_ptr <= (ap1_ptr >= AP1_LEN - 1) ? 0 : (ap1_ptr + 1);
                    ap2_ptr <= (ap2_ptr >= AP2_LEN - 1) ? 0 : (ap2_ptr + 1);
                end
            end
        end
    end

endmodule
