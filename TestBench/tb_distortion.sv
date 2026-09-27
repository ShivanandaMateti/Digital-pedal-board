// =============================================================================
// Testbench: tb_distortion.sv
// Description: Standalone unit test for the distortion module.
//   Tests hard-clipping behavior at configurable drive and threshold settings.
//   Verifies that:
//     - Samples below threshold pass through amplified
//     - Samples above threshold are hard-clipped
//     - Negative samples are clipped symmetrically
//     - Bypass mode passes sample through unchanged
//
// DRIVE_Q8  = 384 (1.5x gain in Q8 fixed-point)
// THRESHOLD = 12000 (clipping limit)
//
// Run with:
//   iverilog -gsystem-verilog -o SIM/tb_dist.vvp RTL/distortion.sv TESTBENCH/tb_distortion.sv
//   vvp SIM/tb_dist.vvp
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

module tb_distortion;

    // DUT connections
    reg              clk;
    reg              rst;
    reg              enable;
    reg              valid_in;
    reg  signed [15:0] sample_in;
    wire             valid_out;
    wire signed [15:0] sample_out;

    // Instantiate distortion with default parameters:
    //   DRIVE_Q8  = 384 (1.5x gain)
    //   THRESHOLD = 12000
    distortion #(
        .DRIVE_Q8  (16'd384),
        .THRESHOLD (16'd12000)
    ) u_dist (
        .clk        (clk),
        .rst        (rst),
        .enable     (enable),
        .valid_in   (valid_in),
        .sample_in  (sample_in),
        .valid_out  (valid_out),
        .sample_out (sample_out)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // Test parameters
    integer pass_count;
    integer fail_count;

    // Task to apply one sample and check result
    // (Verilog-2001 tasks cannot use $display inside, so we do it inline)

    // Helper: apply sample, wait for output, print result
    task apply_sample;
        input signed [15:0] test_in;
        input signed [15:0] expected_out;
        input [63*8:1]      description;
        reg signed [15:0] got;
        begin
            @(posedge clk);
            valid_in  <= 1'b1;
            sample_in <= test_in;
            @(posedge clk);
            valid_in <= 1'b0;
            @(posedge clk); // output registered one cycle later
            got = sample_out;

            if (got === expected_out) begin
                $display("  [PASS] %s: in=%6d -> out=%6d (expected %6d)",
                         description, test_in, got, expected_out);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s: in=%6d -> out=%6d (expected %6d) ***",
                         description, test_in, got, expected_out);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        // Initialize
        rst        = 1'b1;
        enable     = 1'b1;
        valid_in   = 1'b0;
        sample_in  = 16'sh0000;
        pass_count = 0;
        fail_count = 0;

        // Reset for 100 ns
        #100;
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        $display("===============================================================");
        $display("  DISTORTION UNIT TEST");
        $display("  DRIVE_Q8 = 384 (1.5x gain), THRESHOLD = 12000");
        $display("===============================================================");
        $display("  Formula: amplified = (sample_in * 384) >> 8");
        $display("  Clipping: if |amplified| > 12000 => saturate to +/-12000");
        $display("---------------------------------------------------------------");
        $display("  ENABLED CLIPPING TESTS:");

        // Test cases for DRIVE=384, THRESHOLD=12000:
        // amplified = sample * 384 / 256 = sample * 1.5
        //   5000 -> 7500   < 12000 -> output = 7500   (no clip)
        //  10000 -> 15000  > 12000 -> output = 12000  (clipped)
        //  15000 -> 22500  > 12000 -> output = 12000  (clipped)
        //  20000 -> 30000  > 12000 -> output = 12000  (clipped)
        // -5000  -> -7500  > -12000 -> output = -7500  (no clip)
        // -10000 -> -15000 < -12000 -> output = -12000 (clipped)
        // -15000 -> -22500 < -12000 -> output = -12000 (clipped)
        // -20000 -> -30000 < -12000 -> output = -12000 (clipped)
        //   0    ->  0               -> output = 0       (zero)

        apply_sample(16'sd5000,   16'sd7500,  "in= 5000 (no clip)   ");
        apply_sample(16'sd10000,  16'sd12000, "in=10000 (clip +)     ");
        apply_sample(16'sd15000,  16'sd12000, "in=15000 (clip +)     ");
        apply_sample(16'sd20000,  16'sd12000, "in=20000 (clip +)     ");
        apply_sample(-16'sd5000,  -16'sd7500, "in=-5000 (no clip)    ");
        apply_sample(-16'sd10000, -16'sd12000,"in=-10000 (clip -)    ");
        apply_sample(-16'sd15000, -16'sd12000,"in=-15000 (clip -)    ");
        apply_sample(-16'sd20000, -16'sd12000,"in=-20000 (clip -)    ");
        apply_sample(16'sd0,      16'sd0,     "in=0      (zero)      ");

        $display("---------------------------------------------------------------");
        $display("  BYPASS TEST (enable=0):");

        // Bypass: enable=0, output should equal input exactly
        enable = 1'b0;
        apply_sample(16'sd10000,  16'sd10000, "bypass in=10000       ");
        apply_sample(-16'sd10000, -16'sd10000,"bypass in=-10000      ");
        apply_sample(16'sd20000,  16'sd20000, "bypass in=20000       ");

        $display("---------------------------------------------------------------");
        $display("  SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED ✓");
        else
            $display("  RESULT: SOME TESTS FAILED ✗");
        $display("===============================================================");

        $finish;
    end

endmodule
