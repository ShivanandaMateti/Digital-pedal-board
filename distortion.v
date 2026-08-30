module distortion #(
    parameter DATA_WIDTH = 16,
    parameter THRESHOLD  = 12000
)(
    input  wire signed [DATA_WIDTH-1:0] audio_in,
    output reg  signed [DATA_WIDTH-1:0] audio_out
);

    always @(*) begin

        // Positive clipping
        if (audio_in > THRESHOLD)
            audio_out = THRESHOLD;

        // Negative clipping
        else if (audio_in < -THRESHOLD)
            audio_out = -THRESHOLD;

        // Signal within threshold
        else
            audio_out = audio_in;

    end

endmodule
