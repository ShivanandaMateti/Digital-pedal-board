// Code your design here
module distortion #(
    parameter signed [15:0] THRESHOLD = 16'sd10000
)(
    input  logic signed [15:0] sample_in,
    output logic signed [15:0] sample_out
);

    always_comb begin
        if (sample_in > THRESHOLD)
            sample_out = THRESHOLD;
        else if (sample_in < -THRESHOLD)
            sample_out = -THRESHOLD;
        else
            sample_out = sample_in;
    end

endmodule


module delay #(
    parameter integer DELAY_SAMPLES = 2205
)(
    input  logic               clk,
    input  logic               rst,
    input  logic               valid_in,
    input  logic signed [15:0] sample_in,

    output logic               valid_out,
    output logic signed [15:0] sample_out
);

    logic signed [15:0] memory [0:DELAY_SAMPLES-1];

    integer wr_ptr;
    integer i;

    always_ff @(posedge clk) begin

        if (rst) begin
            wr_ptr     <= 0;
            valid_out  <= 1'b0;
            sample_out <= 16'sd0;

            for (i = 0; i < DELAY_SAMPLES; i = i + 1)
                memory[i] <= 16'sd0;
        end

        else begin
            valid_out <= valid_in;

            if (valid_in) begin

                sample_out <= memory[wr_ptr];

                memory[wr_ptr] <= sample_in;

                if (wr_ptr == DELAY_SAMPLES-1)
                    wr_ptr <= 0;
                else
                    wr_ptr <= wr_ptr + 1;

            end
        end

    end

endmodule


module pedalboard_top #(
    parameter signed [15:0] DISTORTION_THRESHOLD = 16'sd10000,
    parameter integer DELAY_SAMPLES = 2205
)(
    input  logic               clk,
    input  logic               rst,

    input  logic [1:0]         effect_select,

    input  logic               valid_in,
    input  logic signed [15:0] sample_in,

    output logic               valid_out,
    output logic signed [15:0] sample_out
);

    logic signed [15:0] distorted_sample;

    logic signed [15:0] delay_input;
    logic signed [15:0] delay_output;
    logic               delay_valid;


    distortion #(
        .THRESHOLD(DISTORTION_THRESHOLD)
    ) u_distortion (
        .sample_in(sample_in),
        .sample_out(distorted_sample)
    );


    always_comb begin

        case (effect_select)

            2'd0: delay_input = sample_in;
            2'd1: delay_input = sample_in;
            2'd2: delay_input = sample_in;
            2'd3: delay_input = distorted_sample;

            default:
                delay_input = sample_in;

        endcase

    end


    delay #(
        .DELAY_SAMPLES(DELAY_SAMPLES)
    ) u_delay (
        .clk(clk),
        .rst(rst),

        .valid_in(
            valid_in &&
            ((effect_select == 2'd2) ||
             (effect_select == 2'd3))
        ),

        .sample_in(delay_input),

        .valid_out(delay_valid),
        .sample_out(delay_output)
    );


    always_comb begin

        case (effect_select)

            // Bypass
            2'd0: begin
                sample_out = sample_in;
                valid_out  = valid_in;
            end

            // Distortion
            2'd1: begin
                sample_out = distorted_sample;
                valid_out  = valid_in;
            end

            // Delay
            2'd2: begin
                sample_out = delay_output;
                valid_out  = delay_valid;
            end

            // Distortion -> Delay
            2'd3: begin
                sample_out = delay_output;
                valid_out  = delay_valid;
            end

            default: begin
                sample_out = sample_in;
                valid_out  = valid_in;
            end

        endcase

    end

endmodule
