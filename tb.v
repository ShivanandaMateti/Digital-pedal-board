`timescale 1ns/1ps

module tb_pedalboard;

    logic clk;
    logic rst;

    logic [1:0] effect_select;

    logic valid_in;
    logic signed [15:0] sample_in;

    logic valid_out;
    logic signed [15:0] sample_out;

    integer input_file;
    integer output_file;

    integer scan_status;
    integer sample_value;

    integer input_count;
    integer output_count;


    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    pedalboard_top #(
        .DISTORTION_THRESHOLD(16'sd10000),
        .DELAY_SAMPLES(10)
    ) dut (

        .clk(clk),
        .rst(rst),

        .effect_select(effect_select),

        .valid_in(valid_in),
        .sample_in(sample_in),

        .valid_out(valid_out),
        .sample_out(sample_out)

    );


    // --------------------------------------------------------
    // CLOCK
    // --------------------------------------------------------

    always #5 clk = ~clk;


    // --------------------------------------------------------
    // MAIN TEST
    // --------------------------------------------------------

    initial begin

        clk = 0;
        rst = 1;

        valid_in = 0;
        sample_in = 0;

        // 0 = bypass
        // 1 = distortion
        // 2 = delay
        // 3 = distortion + delay

        effect_select = 2'd1;


        // ----------------------------------------------------
        // OPEN FILES
        // ----------------------------------------------------

        input_file = $fopen("input_samples_test.txt", "r");

        output_file = $fopen("output_samples.txt", "w");


        if (input_file == 0) begin
            $display("ERROR: Could not open input_samples_test.txt");
            $finish;
        end


        if (output_file == 0) begin
            $display("ERROR: Could not create output_samples.txt");
            $finish;
        end


        input_count = 0;
        output_count = 0;


        // ----------------------------------------------------
        // RESET
        // ----------------------------------------------------

        repeat(5)
            @(posedge clk);

        rst = 0;


        // ----------------------------------------------------
        // READ AUDIO SAMPLES
        // ----------------------------------------------------

        while (!$feof(input_file)) begin

            scan_status = $fscanf(
                input_file,
                "%d\n",
                sample_value
            );


            if (scan_status == 1) begin

                @(negedge clk);

                sample_in = sample_value;

                valid_in = 1'b1;

                input_count = input_count + 1;


                @(negedge clk);

                valid_in = 1'b0;

            end

        end


        // ----------------------------------------------------
        // WAIT FOR FINAL OUTPUT
        // ----------------------------------------------------

        repeat(20)
            @(posedge clk);


        // ----------------------------------------------------
        // CLOSE FILES
        // ----------------------------------------------------

        $fclose(input_file);

        $fclose(output_file);


        $display("------------------------------------");
        $display("Simulation complete");
        $display("Input samples  = %0d", input_count);
        $display("Output samples = %0d", output_count);
        $display("------------------------------------");


        $finish;

    end


    // --------------------------------------------------------
    // WRITE OUTPUT SAMPLES
    // --------------------------------------------------------

    always @(posedge clk) begin

        #1;

        if (valid_out) begin

            $fwrite(
                output_file,
                "%0d\n",
                sample_out
            );

            output_count = output_count + 1;

        end

    end

endmodule
