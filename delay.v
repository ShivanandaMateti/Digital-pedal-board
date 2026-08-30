module delay #(
    parameter DATA_WIDTH = 16,
    parameter MEMORY_SIZE = 48000,
    parameter DELAY_SAMPLES = 4800,
    parameter FEEDBACK = 16'd16384
)(
    input wire clk,
    input wire reset,

    input wire sample_valid,

    input wire signed [DATA_WIDTH-1:0] audio_in,

    output reg signed [DATA_WIDTH-1:0] audio_out
);

    // Delay memory
    reg signed [DATA_WIDTH-1:0] delay_memory [0:MEMORY_SIZE-1];

    integer write_ptr;
    integer read_ptr;

    reg signed [DATA_WIDTH-1:0] delayed_sample;

    reg signed [31:0] feedback_sample;
    reg signed [31:0] new_sample;


    always @(posedge clk) begin

        if (reset) begin

            write_ptr <= 0;
            audio_out <= 0;

        end

        else if (sample_valid) begin

            // Determine read location
            if (write_ptr >= DELAY_SAMPLES)
                read_ptr = write_ptr - DELAY_SAMPLES;
            else
                read_ptr = write_ptr + MEMORY_SIZE - DELAY_SAMPLES;

            // Read delayed sample
            delayed_sample = delay_memory[read_ptr];

            // Output = original + delayed signal
            new_sample = audio_in + (delayed_sample >>> 1);

            // Saturation
            if (new_sample > 32767)
                audio_out <= 32767;

            else if (new_sample < -32768)
                audio_out <= -32768;

            else
                audio_out <= new_sample[DATA_WIDTH-1:0];

            // Feedback
            feedback_sample =
                    audio_in +
                    ((delayed_sample * FEEDBACK) >>> 15);

            // Saturate memory input
            if (feedback_sample > 32767)
                delay_memory[write_ptr] <= 32767;

            else if (feedback_sample < -32768)
                delay_memory[write_ptr] <= -32768;

            else
                delay_memory[write_ptr] <=
                    feedback_sample[DATA_WIDTH-1:0];

            // Circular buffer
            if (write_ptr == MEMORY_SIZE-1)
                write_ptr <= 0;
            else
                write_ptr <= write_ptr + 1;

        end

    end

endmodule
