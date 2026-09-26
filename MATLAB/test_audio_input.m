function test_audio_input()
% Run in MATLAB: test_audio_input
% Tests file/duration options and PCM conversion; no Icarus or audio playback.
    folder = tempname;
    mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder, 's')); %#ok<NASGU>
    Fs = 44100;
    wave = 0.25*sin(2*pi*440*(0:Fs-1)'/Fs);
    input = fullfile(folder, 'my music.wav');
    pcm_file = fullfile(folder, 'pcm.txt');
    audiowrite(input, [wave wave], Fs);
    [pcm, fs, n, meta] = prepare_audio(input, pcm_file, Inf);
    assert(fs == Fs && n == Fs && iscolumn(pcm));
    assert(meta.source_channels == 2 && meta.processed_duration == 1);
    [original, ~] = audioread(input);
    expected = int16(round(mean(original,2)*0.98*32767));
    assert(isequal(pcm, expected));
    [~, ~, n] = prepare_audio(input, pcm_file, 0.25);
    assert(n == 11025);
    [~, ~, n] = prepare_audio(input, pcm_file, 10);
    assert(n == Fs); % Request longer than source must stop at EOF.
    silent = fullfile(folder, 'silent.wav');
    audiowrite(silent, zeros(17,1), Fs);
    [pcm, ~, n] = prepare_audio(silent, pcm_file);
    assert(n == 17 && all(pcm == 0));
    [args, opts] = pedalboard_options({{'wah','delay'}, 'InputFile', input, ...
        'MaxSeconds', 0.25, 'PlayAudio', false, 'TailSeconds', 1});
    assert(isequal(args, {{'wah','delay'}}));
    assert(strcmp(opts.InputFile,input) && opts.MaxSeconds == .25);
    assert(~opts.PlayAudio && opts.TailSeconds == 1);
    [selected, seconds, cancelled] = select_pedalboard_audio(opts, folder);
    assert(strcmp(selected,input) && seconds == .25 && ~cancelled);
    [args, opts] = pedalboard_options({'delay', 'InputFile', input, 'MaxSeconds', 'full'});
    assert(isequal(args, {'delay'}) && isinf(opts.MaxSeconds));
    [~, opts] = pedalboard_options({});
    assert(isempty(opts.InputFile) && isinf(opts.MaxSeconds) && ~opts.DurationSpecified);
    bad = {{'MaxSeconds', 0}, {'MaxSeconds', NaN}, {'MaxSeconds', -1}, ...
        {'MaxSeconds', [1 2]}, {'InputFile'}, {'PlayAudio', 2}, {'TailSeconds', Inf}};
    for k = 1:numel(bad)
        failed = false;
        try
            pedalboard_options(bad{k});
        catch
            failed = true;
        end
        assert(failed, 'Invalid option was accepted.');
    end
    if exist('resample', 'file') ~= 0
        source = fullfile(folder, '48000.wav');
        audiowrite(source, .2*sin(2*pi*440*(0:47999)'/48000), 48000);
        [~,fs,n] = prepare_audio(source, pcm_file, .25);
        assert(fs == 44100 && n == 11025);
    else
        fprintf('Resampling test skipped: Signal Processing Toolbox unavailable.\n');
    end
    fprintf('PASS: audio options, full/partial reads, stereo, silence, size, invalid options.\n');
end
