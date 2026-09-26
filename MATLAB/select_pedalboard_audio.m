function [input_file, max_seconds, cancelled] = select_pedalboard_audio(opts, start_dir)
% File/duration picker. Supplying InputFile makes the call noninteractive.
    input_file = opts.InputFile;
    max_seconds = opts.MaxSeconds;
    cancelled = false;
    if ~isempty(input_file), return; end
    if ~usejava('desktop')
        error('pedalboard:InputRequired', ...
            'No desktop file picker is available. Supply ''InputFile'', ''full/path/to/audio.wav''.');
    end
    [name, folder] = uigetfile( ...
        {'*.wav;*.mp3;*.flac;*.m4a;*.ogg;*.aif;*.aiff', 'Audio files'; ...
         '*.*', 'All files'}, 'Choose an input audio file', start_dir);
    if isequal(name, 0), cancelled = true; return; end
    input_file = fullfile(folder, name);
    if opts.DurationSpecified, return; end
    info = audioinfo(input_file);
    prompt = sprintf(['Audio length: %.2f seconds.\n' ...
        'Enter full, or seconds to process from the beginning (e.g. 10).\n' ...
        'Long clips take longer to simulate.'], info.Duration);
    while true
        answer = inputdlg(prompt, 'Audio duration', [3 65], {'full'});
        if isempty(answer), cancelled = true; return; end
        entry = strtrim(answer{1});
        if strcmpi(entry, 'full')
            max_seconds = Inf;
            return;
        end
        seconds = str2double(entry);
        if isscalar(seconds) && isfinite(seconds) && seconds > 0
            max_seconds = seconds;
            return;
        end
        uiwait(errordlg('Enter full or a positive duration in seconds.', 'Invalid duration'));
    end
end
