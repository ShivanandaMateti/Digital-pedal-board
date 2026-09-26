function [audio_out, Fs] = reconstruct_audio(output_txt, output_wav, Fs, play_audio)
% =============================================================================
% Function: reconstruct_audio.m
% Description: Reads RTL simulation output (signed decimal PCM integers from
%              output_samples.txt), converts back to normalized floating-point
%              audio [-1, +1], and writes to a 16-bit WAV file.
%              Optionally plays the audio through laptop speakers.
%
% Inputs:
%   output_txt  - Full path to output_samples.txt (written by vvp simulation)
%   output_wav  - Full path to write output.wav
%   Fs          - Sample rate to use when writing WAV (must be 44100)
%   play_audio  - Boolean: if true, play via MATLAB soundsc()
%
% Outputs:
%   audio_out   - Floating-point normalized audio column vector
%   Fs          - Sample rate (passthrough)
% =============================================================================

    if nargin < 4, play_audio = false; end
    if nargin < 3, Fs = 44100; end

    % --- Check output_samples.txt exists ---
    if ~exist(output_txt, 'file')
        error(['ERROR: RTL simulation did not generate output_samples.txt.\n' ...
               'Expected location: %s\n' ...
               'Check that the simulation ran correctly (see console output above).'], ...
               output_txt);
    end

    % --- Read PCM integer samples ---
    fprintf('  Reading output samples from: %s\n', output_txt);
    fid = fopen(output_txt, 'r');
    if fid == -1
        error('ERROR: Could not open %s for reading.', output_txt);
    end
    raw = textscan(fid, '%d');
    fclose(fid);
    pcm_out = double(raw{1});

    if isempty(pcm_out)
        error(['ERROR: output_samples.txt is empty.\n' ...
               'The RTL simulation may have failed to produce output.\n' ...
               'Possible causes:\n' ...
               '  1. input_samples.txt was empty.\n' ...
               '  2. The simulation ended before producing valid_out.\n' ...
               '  3. All effects are disabled AND the pipeline has latency.']);
    end

    num_out = length(pcm_out);
    fprintf('  Read %d output samples.\n', num_out);

    % --- Convert PCM integers to normalized float [-1, +1] ---
    audio_out = double(pcm_out) / 32768.0;

    % --- Clamp to [-1, +1] (should already be within range) ---
    audio_out = max(-1.0, min(1.0, audio_out));

    % --- Write output.wav ---
    audiowrite(output_wav, audio_out, Fs, 'BitsPerSample', 16);
    fprintf('  Written: %s (%d samples, %.2f s @ %d Hz)\n\n', ...
            output_wav, num_out, num_out/Fs, Fs);

    % --- Play audio through speakers ---
    if play_audio
        fprintf('  Playing output through speakers (%.1f s)...\n', num_out/Fs);
        try
            sound(audio_out, Fs);
            fprintf('  Playback started. (Non-blocking — MATLAB continues.)\n');
        catch ME
            fprintf('  [Note] Audio playback skipped: %s\n', ME.message);
        end
    end
end
