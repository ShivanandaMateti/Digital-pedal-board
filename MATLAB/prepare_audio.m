function [pcm_samples, Fs, num_samples, meta] = prepare_audio(input_file, input_txt, max_seconds)
% Read selected audio (full file or a prefix), convert to mono/44.1kHz/16-bit PCM.
% max_seconds defaults to Inf. Finite requests read only that source range.
    if nargin < 3 || isempty(max_seconds), max_seconds = Inf; end
    validateattributes(max_seconds, {'numeric'}, {'scalar','real','positive','nonnan'});
    TARGET_FS = 44100;
    if ~isfile(input_file)
        error('pedalboard:InputMissing', 'Audio file not found: %s', input_file);
    end
    info = audioinfo(input_file);
    if info.TotalSamples < 1
        error('pedalboard:EmptyAudio', 'The selected audio file has no samples.');
    end
    file_info = dir(input_file);
    fprintf('  Input: %s\n', input_file);
    fprintf('  Source: %.2f s, %d Hz, %d channel(s), %.3f MB\n', ...
        info.Duration, info.SampleRate, info.NumChannels, file_info(1).bytes/1e6);
    if isinf(max_seconds)
        [audio_data, Fs_orig] = audioread(input_file);
    else
        requested_source = max(1, ceil(max_seconds * info.SampleRate));
        last_sample = min(info.TotalSamples, requested_source);
        [audio_data, Fs_orig] = audioread(input_file, [1 last_sample]);
    end
    if isempty(audio_data)
        error('pedalboard:EmptyAudio', 'No audio samples were decoded.');
    end
    if any(~isfinite(audio_data(:)))
        error('pedalboard:InvalidAudio', 'Audio contains non-finite samples.');
    end
    decoded_samples = size(audio_data, 1);
    if size(audio_data, 2) > 1
        audio_data = mean(audio_data, 2);
        fprintf('  Converted to mono.\n');
    end
    if Fs_orig ~= TARGET_FS
        if exist('resample', 'file') == 0
            error('pedalboard:ResampleUnavailable', ...
                ['This file is %d Hz. Install Signal Processing Toolbox for resample, ' ...
                 'or supply a 44100 Hz WAV file.'], Fs_orig);
        end
        divisor = gcd(TARGET_FS, Fs_orig);
        audio_data = resample(audio_data, TARGET_FS/divisor, Fs_orig/divisor);
        fprintf('  Resampled to %d Hz.\n', TARGET_FS);
    end
    Fs = TARGET_FS;
    if isfinite(max_seconds)
        max_samples = max(1, round(max_seconds * Fs));
        audio_data = audio_data(1:min(numel(audio_data), max_samples));
    end
    peak = max(abs(audio_data));
    if peak > 1
        audio_data = audio_data / peak;
    elseif peak < 1e-9
        fprintf('  Note: selected audio is silent; processing silence.\n');
    end
    pcm = round(audio_data * 0.98 * 32767);
    pcm_samples = int16(max(-32768, min(32767, pcm)));
    num_samples = numel(pcm_samples);
    fid = fopen(input_txt, 'w');
    if fid == -1, error('Cannot write PCM samples to %s.', input_txt); end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%d\n', pcm_samples);
    meta = struct('input_file', input_file, 'source_bytes', file_info(1).bytes, ...
        'source_duration', info.Duration, 'source_sample_rate', info.SampleRate, ...
        'source_channels', info.NumChannels, 'decoded_samples', decoded_samples, ...
        'processed_duration', num_samples/Fs, 'processed_samples', num_samples);
    fprintf('  Prepared %d samples (%.3f seconds at %d Hz).\n\n', num_samples, num_samples/Fs, Fs);
end
