function stats = verify_effects(in_file, out_file, cfg)
% =============================================================================
% Function: verify_effects.m
% Description: Reads input_samples.txt and output_samples.txt, performs numerical
%              verification (sample counts, min/max, peak, RMS, clipping limits,
%              and bypass fidelity), and plots time and frequency comparisons.
%
% Inputs:
%   in_file  - Path to input_samples.txt
%   out_file - Path to output_samples.txt
%   cfg      - (Optional) Struct containing FX enable flags and parameters
%
% Outputs:
%   stats    - Struct with numerical analysis results
% =============================================================================

    if nargin < 1 || isempty(in_file),  in_file  = 'MATLAB/input_samples.txt'; end
    if nargin < 2 || isempty(out_file), out_file = 'MATLAB/output_samples.txt'; end
    if nargin < 3, cfg = struct(); end

    fprintf('===============================================================\n');
    fprintf('DIGITAL GUITAR PEDALBOARD - VERIFICATION & ANALYSIS\n');
    fprintf('===============================================================\n');

    % 1. Read input samples
    fid_in = fopen(in_file, 'r');
    if fid_in == -1, error('ERROR: Could not open %s', in_file); end
    data_in = textscan(fid_in, '%d');
    fclose(fid_in);
    in_pcm = double(data_in{1});

    % 2. Read output samples
    fid_out = fopen(out_file, 'r');
    if fid_out == -1, error('ERROR: Could not open %s', out_file); end
    data_out = textscan(fid_out, '%d');
    fclose(fid_out);
    out_pcm = double(data_out{1});

    N_in  = length(in_pcm);
    N_out = length(out_pcm);
    N_eval = min(N_in, N_out);

    % 3. Calculate statistical metrics
    stats = struct();
    stats.N_in       = N_in;
    stats.N_out      = N_out;
    stats.in_min     = min(in_pcm);
    stats.in_max     = max(in_pcm);
    stats.in_peak    = max(abs(in_pcm));
    stats.in_rms     = sqrt(mean(in_pcm.^2));

    stats.out_min    = min(out_pcm);
    stats.out_max    = max(out_pcm);
    stats.out_peak   = max(abs(out_pcm));
    stats.out_rms    = sqrt(mean(out_pcm.^2));

    % Print Summary Table
    fprintf('%-24s | %-16s | %-16s\n', 'Metric', 'Input (PCM)', 'Output (PCM)');
    fprintf('-------------------------+------------------+------------------\n');
    fprintf('%-24s | %-16d | %-16d\n', 'Total Sample Count', stats.N_in, stats.N_out);
    fprintf('%-24s | %-16d | %-16d\n', 'Minimum Sample Value', stats.in_min, stats.out_min);
    fprintf('%-24s | %-16d | %-16d\n', 'Maximum Sample Value', stats.in_max, stats.out_max);
    fprintf('%-24s | %-16d | %-16d\n', 'Peak Absolute Value', stats.in_peak, stats.out_peak);
    fprintf('%-24s | %-16.2f | %-16.2f\n', 'RMS Level', stats.in_rms, stats.out_rms);
    fprintf('-------------------------+------------------+------------------\n');

    expected_tail = 0;
    if isfield(cfg, 'TAIL_SAMPLES'), expected_tail = cfg.TAIL_SAMPLES; end
    stats.expected_samples = N_in + expected_tail;
    if N_out ~= stats.expected_samples
        error('Output sample count mismatch: expected %d, got %d.', stats.expected_samples, N_out);
    end
    % A downstream effect can legitimately exceed the distortion clip limit.
    downstream_active = false;
    if isfield(cfg, 'FX')
        downstream = {'phaser','chorus','tremolo','delay','reverb','looper'};
        for k = 1:numel(downstream)
            if isfield(cfg.FX, downstream{k}) && cfg.FX.(downstream{k})
                downstream_active = true;
            end
        end
    end
    % 4. Check the final output only when distortion has no active successor.
    if isfield(cfg, 'DIST_THRESHOLD') && isfield(cfg, 'FX') && isfield(cfg.FX, 'distortion') && cfg.FX.distortion && ~downstream_active
        thresh = cfg.DIST_THRESHOLD;
        max_clipped = max(out_pcm);
        min_clipped = min(out_pcm);
        fprintf('\nDISTORTION HARD-CLIPPING CHECK (Threshold = %0d):\n', thresh);
        if max_clipped <= thresh && min_clipped >= -thresh
            fprintf('  [PASS] Output strictly bounded by [-THRESHOLD, +THRESHOLD]. Max: %0d, Min: %0d\n', ...
                    max_clipped, min_clipped);
        else
            fprintf('  [FAIL] Output exceeded clipping bounds! Max: %0d, Min: %0d\n', ...
                    max_clipped, min_clipped);
        end
    end

    % 5. Bypass Verification (if all effects disabled)
    all_bypass = false;
    if isfield(cfg, 'FX')
        fnames = fieldnames(cfg.FX);
        active_count = 0;
        for i = 1:length(fnames)
            if cfg.FX.(fnames{i}), active_count = active_count + 1; end
        end
        if active_count == 0, all_bypass = true; end
    end

    if all_bypass && N_eval > 0
        diff_samples = abs(in_pcm(1:N_eval) - out_pcm(1:N_eval));
        max_err = max(diff_samples);
        mean_err = mean(diff_samples);
        corr_val = corrcoef(in_pcm(1:N_eval), out_pcm(1:N_eval));
        stats.bypass_corr = corr_val(1,2);
        stats.bypass_max_err = max_err;

        fprintf('\nBYPASS FIDELITY CHECK (All Effects Disabled):\n');
        fprintf('  Maximum Absolute Error: %0d LSB\n', max_err);
        fprintf('  Mean Absolute Error:    %0.4f LSB\n', mean_err);
        fprintf('  Signal Correlation:     %0.6f\n', stats.bypass_corr);
        if max_err == 0
            fprintf('  [PASS] BIT-EXACT BYPASS: Output exactly matches input!\n');
        elseif stats.bypass_corr > 0.9999
            fprintf('  [PASS] BYPASS MATCH: High fidelity signal match.\n');
        else
            fprintf('  [WARNING] Significant difference detected during bypass.\n');
        end
    end

    % 6. Plotting
    try
        Fs = 44100;
        t_in  = (0:N_in-1)  / Fs;
        t_out = (0:N_out-1) / Fs;

        fig = figure('Name', 'Digital Pedalboard - Waveform Analysis', ...
                     'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 1000, 700]);

        % Top: Full Waveform Comparison
        subplot(3, 1, 1);
        plot(t_in, in_pcm / 32767.0, 'Color', [0.2, 0.4, 0.8], 'LineWidth', 1.0);
        hold on;
        plot(t_out, out_pcm / 32767.0, 'Color', [0.85, 0.3, 0.1], 'LineWidth', 0.8);
        grid on;
        legend('Input (guitar.wav)', 'Output (output.wav)', 'Location', 'northeast');
        title('Full Signal Waveform Comparison');
        xlabel('Time (seconds)');
        ylabel('Normalized Amplitude');
        xlim([0, min(max(t_in), max(t_out))]);
        ylim([-1.1, 1.1]);

        % Middle: Zoomed-in Segment (e.g. 50 ms window showing waveshape alteration)
        subplot(3, 1, 2);
        zoom_start = 0.5; % 0.5 s
        zoom_dur   = 0.04; % 40 ms
        zoom_idx_in  = find(t_in >= zoom_start & t_in <= zoom_start + zoom_dur);
        zoom_idx_out = find(t_out >= zoom_start & t_out <= zoom_start + zoom_dur);

        if ~isempty(zoom_idx_in) && ~isempty(zoom_idx_out)
            plot(t_in(zoom_idx_in), in_pcm(zoom_idx_in) / 32767.0, 'b-o', 'LineWidth', 1.2, 'MarkerSize', 3);
            hold on;
            plot(t_out(zoom_idx_out), out_pcm(zoom_idx_out) / 32767.0, 'r-x', 'LineWidth', 1.2, 'MarkerSize', 3);
            grid on;
            legend('Input', 'Output', 'Location', 'northeast');
            title(sprintf('Zoomed Waveform Segment (t = %0.3f s to %0.3f s)', zoom_start, zoom_start + zoom_dur));
            xlabel('Time (seconds)');
            ylabel('Normalized Amplitude');
        end

        % Bottom: Frequency Spectrum (FFT)
        subplot(3, 1, 3);
        nfft = 2^nextpow2(min(8192, N_eval));
        if nfft > 128
            f_axis = (0:(nfft/2)-1) * (Fs / nfft);
            if exist('hann', 'file')
                win = hann(nfft);
            else
                % Inline Hann window (base MATLAB compatible)
                win = 0.5 * (1 - cos(2 * pi * (0:nfft-1)' / (nfft - 1)));
            end
            in_seg  = in_pcm(1:nfft) / 32767.0;
            out_seg = out_pcm(1:nfft) / 32767.0;

            in_fft  = abs(fft(in_seg .* win, nfft));
            out_fft = abs(fft(out_seg .* win, nfft));

            in_db  = 20 * log10(in_fft(1:nfft/2) + 1e-6);
            out_db = 20 * log10(out_fft(1:nfft/2) + 1e-6);

            plot(f_axis, in_db, 'Color', [0.2, 0.4, 0.8], 'LineWidth', 1.0);
            hold on;
            plot(f_axis, out_db, 'Color', [0.85, 0.3, 0.1], 'LineWidth', 1.0);
            grid on;
            legend('Input Spectrum', 'Output Spectrum', 'Location', 'northeast');
            title('Frequency Spectrum Magnitude (FFT Segment)');
            xlabel('Frequency (Hz)');
            ylabel('Magnitude (dB)');
            xlim([20, 8000]);
        end

        drawnow;
    catch ME
        fprintf('  [Note] Waveform plotting skipped: %s\n', ME.message);
    end

    fprintf('===============================================================\n\n');
end
