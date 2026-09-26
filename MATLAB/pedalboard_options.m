function [effect_args, opts] = pedalboard_options(args)
% Separate audio options from the existing effect selectors.
    opts = struct('InputFile', '', 'MaxSeconds', Inf, ...
                  'DurationSpecified', false, 'PlayAudio', true, 'TailSeconds', 3);
    effect_args = {};
    k = 1;
    while k <= numel(args)
        arg = args{k};
        is_text = ischar(arg) || (isstring(arg) && isscalar(arg));
        if is_text, key = lower(char(arg)); else, key = ''; end
        if any(strcmp(key, {'inputfile','maxseconds','playaudio','tailseconds'}))
            if k == numel(args)
                error('pedalboard:MissingOptionValue', 'Missing value for %s.', key);
            end
            value = args{k+1};
            switch key
                case 'inputfile'
                    if ~(ischar(value) && (isrow(value) || isempty(value))) && ...
                       ~(isstring(value) && isscalar(value))
                        error('pedalboard:InvalidInputFile', 'InputFile must be a file path.');
                    end
                    opts.InputFile = char(value);
                case 'maxseconds'
                    if (ischar(value) || (isstring(value) && isscalar(value))) && ...
                            strcmpi(strtrim(char(value)), 'full')
                        value = Inf;
                    end
                    validateattributes(value, {'numeric'}, {'scalar','real','positive','nonnan'});
                    opts.MaxSeconds = double(value);
                    opts.DurationSpecified = true;
                case 'playaudio'
                    validateattributes(value, {'logical','numeric'}, {'scalar','real','finite'});
                    if value ~= 0 && value ~= 1
                        error('pedalboard:InvalidPlayAudio', 'PlayAudio must be true or false.');
                    end
                    opts.PlayAudio = logical(value);
                case 'tailseconds'
                    validateattributes(value, {'numeric'}, {'scalar','real','finite','nonnegative'});
                    opts.TailSeconds = double(value);
            end
            k = k+2;
        else
            effect_args{end+1} = arg; %#ok<AGROW>
            k = k+1;
        end
    end
end
