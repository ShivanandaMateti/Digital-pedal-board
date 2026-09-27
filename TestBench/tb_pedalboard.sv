// =============================================================================
// Testbench: tb_pedalboard.sv
// Description: Offline top-level audio simulation testbench.
//   Reads signed decimal 16-bit PCM samples from MATLAB/input_samples.txt,
//   streams them through pedalboard_top, and records outputs to
//   MATLAB/output_samples.txt.
//
// File paths: Written relative to where vvp is invoked.
//   Run vvp from the Digital_Pedalboard project root:
//     vvp SIM/pedalboard_sim.vvp
//
// Verilog-2001 compatible (works with Icarus Verilog v0.9.7+)
// =============================================================================

`timescale 1ns / 1ps

`include "sim_config.svh"

`ifndef CFG_TAIL_SAMPLES
`define CFG_TAIL_SAMPLES 0
`endif

module tb_pedalboard;

    reg              clk;
    reg              rst;
    wire [8:0]       enable_fx;
    reg              valid_in;
    reg  signed [15:0] sample_in;
    wire             valid_out;
    wire signed [15:0] sample_out;

    // Connect effect enable bits from sim_config.svh defines
    assign enable_fx[0] = `CFG_ENABLE_PITCH;
    assign enable_fx[1] = `CFG_ENABLE_WAH;
    assign enable_fx[2] = `CFG_ENABLE_DISTORTION;
    assign enable_fx[3] = `CFG_ENABLE_PHASER;
    assign enable_fx[4] = `CFG_ENABLE_CHORUS;
    assign enable_fx[5] = `CFG_ENABLE_TREMOLO;
    assign enable_fx[6] = `CFG_ENABLE_DELAY;
    assign enable_fx[7] = `CFG_ENABLE_REVERB;
    assign enable_fx[8] = `CFG_ENABLE_LOOPER;

    // Instantiate the top-level pedalboard
    pedalboard_top #(
        .PITCH_MODE     (`CFG_PITCH_MODE),
        .DIST_DRIVE     (`CFG_DIST_DRIVE),
        .DIST_THRESHOLD (`CFG_DIST_THRESHOLD),
        .DELAY_MS       (`CFG_DELAY_MS),
        .DELAY_WET      (`CFG_DELAY_WET),
        .DELAY_FEEDBACK (`CFG_DELAY_FEEDBACK),
        .LOOP_MS        (`CFG_LOOP_MS)
    ) u_pedalboard (
        .clk        (clk),
        .rst        (rst),
        .enable_fx  (enable_fx),
        .valid_in   (valid_in),
        .sample_in  (sample_in),
        .valid_out  (valid_out),
        .sample_out (sample_out)
    );

    // Clock: 100 MHz (10 ns period) — much faster than audio clock,
    // allows pipeline to settle between samples
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // File handles and counters
    integer in_file, out_file;
    integer in_sample_int;
    integer input_count;
    integer output_count;
    integer scan_ret;
    integer flush_cycles;
    integer tail_index;
    integer k;

    // Concurrent output collector
    always @(posedge clk) begin
        if (!rst && valid_out) begin
            $fdisplay(out_file, "%d", sample_out);
            output_count = output_count + 1;
        end
    end

    initial begin
        // Initialize signals
        clk          = 1'b0;
        rst          = 1'b1;
        valid_in     = 1'b0;
        sample_in    = 16'sh0000;
        input_count  = 0;
        output_count = 0;

        // Open input file — try multiple relative paths (run from project root)
        in_file = $fopen("MATLAB/input_samples.txt", "r");
        if (in_file == 0)
            in_file = $fopen("Digital_Pedalboard/MATLAB/input_samples.txt", "r");
        if (in_file == 0)
            in_file = $fopen("input_samples.txt", "r");

        if (in_file == 0) begin
            $display("ERROR: Could not open input_samples.txt!");
            $display("  Please run MATLAB/run_pedalboard.m or prepare_audio.m first.");
            $display("  Then run vvp from the Digital_Pedalboard/ project root.");
            $finish;
        end

        // Open output file — write to same relative location as input
        out_file = $fopen("MATLAB/output_samples.txt", "w");
        if (out_file == 0)
            out_file = $fopen("Digital_Pedalboard/MATLAB/output_samples.txt", "w");
        if (out_file == 0)
            out_file = $fopen("output_samples.txt", "w");

        if (out_file == 0) begin
            $display("ERROR: Could not open output_samples.txt for writing!");
            $finish;
        end

        // Print simulation header
        $display("===============================================================");
        $display("  DIGITAL GUITAR PEDALBOARD - RTL AUDIO SIMULATION");
        $display("===============================================================");
        $display("  Effect Configuration:");
        $display("  [0] Pitch Shift: %s (Mode %0d)", enable_fx[0] ? "ON " : "OFF", `CFG_PITCH_MODE);
        $display("  [1] Auto-Wah:    %s",            enable_fx[1] ? "ON " : "OFF");
        $display("  [2] Distortion:  %s (Drive=%0d, Thresh=%0d)",
                 enable_fx[2] ? "ON " : "OFF", `CFG_DIST_DRIVE, `CFG_DIST_THRESHOLD);
        $display("  [3] Phaser:      %s",            enable_fx[3] ? "ON " : "OFF");
        $display("  [4] Chorus:      %s",            enable_fx[4] ? "ON " : "OFF");
        $display("  [5] Tremolo:     %s",            enable_fx[5] ? "ON " : "OFF");
        $display("  [6] Delay/Echo:  %s (%0d ms)",  enable_fx[6] ? "ON " : "OFF", `CFG_DELAY_MS);
        $display("  [7] Reverb:      %s",            enable_fx[7] ? "ON " : "OFF");
        $display("  [8] Looper:      %s (%0d ms)",  enable_fx[8] ? "ON " : "OFF", `CFG_LOOP_MS);
        $display("===============================================================");

        // Reset sequence: hold rst high for 100 ns
        #100;
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // =====================================================================
        // Stream audio samples one per clock cycle
        // =====================================================================
        scan_ret = $fscanf(in_file, "%d\n", in_sample_int);
        while (scan_ret == 1) begin
            @(posedge clk);
            valid_in  <= 1'b1;
            sample_in <= in_sample_int[15:0];
            input_count = input_count + 1;

            @(posedge clk);
            valid_in <= 1'b0;

            // Progress update every 10000 samples
            if ((input_count % 10000) == 0)
                $display("  Progress: %0d samples processed...", input_count);

            scan_ret = $fscanf(in_file, "%d\n", in_sample_int);
        end

        // Feed valid zero samples so effect memories can decay after EOF.
        // Idle clock cycles alone do not advance these sample-driven effects.
        for (tail_index = 0; tail_index < `CFG_TAIL_SAMPLES; tail_index = tail_index + 1) begin
            @(posedge clk);
            valid_in <= 1'b1;
            sample_in <= 16'sd0;
            @(posedge clk);
            valid_in <= 1'b0;
        end

        // =====================================================================
        // Pipeline flush: wait 50 cycles for all stages to drain
        // =====================================================================
        for (flush_cycles = 0; flush_cycles < 50; flush_cycles = flush_cycles + 1)
            @(posedge clk);

        @(negedge clk); // Output collector has finished for this cycle.
        $fclose(in_file);
        $fclose(out_file);

        // Print simulation summary
        $display("===============================================================");
        $display("  SIMULATION COMPLETE");
        $display("  Total Input Samples:  %0d", input_count);
        $display("  Total Output Samples: %0d", output_count);
        $display("===============================================================");

        if (output_count != input_count + `CFG_TAIL_SAMPLES)
            $fatal(1, "Output count mismatch: expected %0d got %0d", input_count + `CFG_TAIL_SAMPLES, output_count);
        $display("  Tail Samples: %0d", `CFG_TAIL_SAMPLES);
        if (input_count > 0 && output_count > 0) begin
            $display("  SUCCESS: RTL effects chain processed audio.");
        end else if (input_count == 0) begin
            $display("  WARNING: No input samples were read. Check input_samples.txt.");
        end else begin
            $display("  NOTE: In=%0d Out=%0d (pipeline latency may account for difference)",
                     input_count, output_count);
        end

        $finish;
    end

endmodule
