function [audio_out, stats] = run_pedalboard(varargin)
% =============================================================================
% Script/Function: run_pedalboard.m
% Description: MASTER USER SCRIPT for the Digital Guitar Pedalboard.
%              Enables/disables effects, converts audio, compiles RTL,
%              runs the simulation, reconstructs output, and plots results.
%
% USAGE:
%   Method 1 (recommended): Edit EFFECT below, press Run (F5 in MATLAB).
%   Method 2 (command window):
%       run_pedalboard(2)              % Distortion; choose audio and duration
%       run_pedalboard('wah', 'InputFile', 'C:\Music\song.wav', 'MaxSeconds', 10)
%       run_pedalboard({'distortion','delay'}, 'InputFile', 'song.wav') % full clip
%       run_pedalboard('wah')          % Wah
%       run_pedalboard('bypass')       % All effects off (bypass test)
%       run_pedalboard([2, 6])         % Distortion + Delay together
% =============================================================================

%% ===========================================================================
% SECTION 1: USER CONFIGURATION — CHANGE EFFECT HERE
% ===========================================================================
%
%   ID   NAME           DESCRIPTION
%  -----------------------------------------------------------------------
%    0 | 'pitch'      | Pitch / Octave Effect
%    1 | 'wah'        | Auto-Wah (LFO-swept bandpass)
%    2 | 'distortion' | Guitar Distortion (hard clipping)
%    3 | 'phaser'     | 4-Stage All-Pass Phaser
%    4 | 'chorus'     | Modulated Delay Chorus
%    5 | 'tremolo'    | Tremolo (LFO amplitude modulation)
%    6 | 'delay'      | Delay / Echo (circular buffer)
%    7 | 'reverb'     | Multi-comb Schroeder Reverb
%    8 | 'looper'     | Phrase Looper (record then replay)
%   -1 | 'bypass'     | All effects OFF — clean passthrough
%  -----------------------------------------------------------------------
%
% >>> CHANGE THIS LINE TO SELECT YOUR EFFECT <<<
EFFECT = 2;   % e.g. 2, 'distortion', 'delay', 'bypass', -1, [2,6], etc.

% Internal effect enable struct (all start as false)
FX = struct('pitch',false,'wah',false,'distortion',true,'phaser',false, ...
            'chorus',false,'tremolo',false,'delay',false,'reverb',false,'looper',false);

% Apply the EFFECT selection defined above
FX = parse_effect_selection(FX, EFFECT);

%% ===========================================================================
% SECTION 2: EFFECT PARAMETERS
% ===========================================================================

% --- Pitch ---
PITCH_MODE       = 1;      % 1 = Octave Up, 2 = Octave Down

% --- Distortion ---
DIST_DRIVE       = 384;    % Q8 gain: 256=1.0x, 384=1.5x, 512=2.0x
DIST_THRESHOLD   = 12000;  % Hard clip limit (max 32767)

% --- Delay / Echo ---
DELAY_MS         = 250;    % Delay time in ms (10-500)
DELAY_WET        = 16384;  % Q15 wet mix (0=dry, 32767=full wet)
DELAY_FEEDBACK   = 14745;  % Q15 feedback (~45%, must be < 28000 for stability)

% --- Looper ---
LOOP_MS          = 500;    % Loop buffer length in milliseconds

% --- Simulation control ---
MAX_SECONDS      = Inf;    % Full selected clip by default; override with MaxSeconds
TAIL_SECONDS     = 3.0;    % Extra silence for delay/reverb decay (no looper)
PLAY_AUDIO       = true;   % Play output.wav through speakers when done

%% ===========================================================================
% SECTION 3: COMMAND-LINE ARGUMENT PARSING
% ===========================================================================
[effect_args, audio_opts] = pedalboard_options(varargin);
MAX_SECONDS = audio_opts.MaxSeconds;
PLAY_AUDIO = audio_opts.PlayAudio;
TAIL_SECONDS = audio_opts.TailSeconds;
audio_out = [];
stats = struct();
% Explicit effect lists start with no effects enabled (avoid implicit distortion).
if ~isempty(effect_args)
    FX = parse_effect_selection(FX, []);
end
if numel(effect_args) == 1
    arg1 = effect_args{1};
    if isstruct(arg1)
        fns = fieldnames(arg1);
        for k = 1:length(fns)
            key = lower(fns{k});
            if isfield(FX, key), FX.(key) = logical(arg1.(fns{k})); end
        end
    else
        FX = parse_effect_selection(FX, arg1);
    end
elseif numel(effect_args) >= 2
    idx = 1;
    while idx <= length(effect_args)
        arg = effect_args{idx};
        if ischar(arg) || isstring(arg)
            key = lower(char(arg));
            if strcmp(key, 'bypass')
                fns = fieldnames(FX);
                for k = 1:length(fns), FX.(fns{k}) = false; end
            elseif isfield(FX, key)
                if idx < length(effect_args) && ...
                   (islogical(effect_args{idx+1}) || isnumeric(effect_args{idx+1}))
                    FX.(key) = logical(effect_args{idx+1});
                    idx = idx + 1;
                else
                    FX.(key) = true;
                end
            end
        elseif isnumeric(arg)
            FX = parse_effect_selection(FX, arg);
        end
        idx = idx + 1;
    end
end

%% ===========================================================================
% SECTION 4: RESOLVE PROJECT PATHS
% ===========================================================================
script_path = mfilename('fullpath');
if isempty(script_path)
    script_dir = pwd;
else
    script_dir = fileparts(script_path);
end

% Find MATLAB dir and project root
if exist(fullfile(script_dir, 'prepare_audio.m'), 'file')
    matlab_dir   = script_dir;
    project_root = fullfile(script_dir, '..');
elseif exist(fullfile(pwd, 'Digital_Pedalboard', 'MATLAB', 'run_pedalboard.m'), 'file')
    matlab_dir   = fullfile(pwd, 'Digital_Pedalboard', 'MATLAB');
    project_root = fullfile(pwd, 'Digital_Pedalboard');
else
    matlab_dir   = script_dir;
    project_root = fullfile(script_dir, '..');
end

% Canonical absolute paths
project_root = char(java.io.File(project_root).getCanonicalPath());
matlab_dir   = char(java.io.File(matlab_dir).getCanonicalPath());

addpath(matlab_dir);

audio_dir  = fullfile(project_root, 'AUDIO');
rtl_dir    = fullfile(project_root, 'RTL');
tb_dir     = fullfile(project_root, 'TESTBENCH');
sim_dir    = fullfile(project_root, 'SIM');

[input_wav, MAX_SECONDS, cancelled] = select_pedalboard_audio(audio_opts, audio_dir);
if cancelled
    fprintf('Audio selection cancelled. No processing was started.\n');
    stats.cancelled = true;
    return;
end
input_wav = char(java.io.File(input_wav).getCanonicalPath());
output_wav = fullfile(audio_dir, 'output.wav');
% Never overwrite a selected input that happens to be the previous output.
if (ispc && strcmpi(input_wav, output_wav)) || strcmp(input_wav, output_wav)
    output_wav = fullfile(audio_dir, 'processed_output.wav');
end
input_txt  = fullfile(matlab_dir, 'input_samples.txt');
output_txt = fullfile(matlab_dir, 'output_samples.txt');
sim_header = fullfile(sim_dir, 'sim_config.svh');

fprintf('===============================================================\n');
fprintf('       DIGITAL GUITAR PEDALBOARD - OFFLINE RTL ENGINE\n');
fprintf('===============================================================\n');
fprintf('Project root: %s\n\n', project_root);
fprintf('Active Effects:\n');
fprintf('  Pitch:%-6s  Wah:%-6s  Distortion:%-6s\n', ...
        yn(FX.pitch), yn(FX.wah), yn(FX.distortion));
fprintf('  Phaser:%-6s Chorus:%-6s Tremolo:%-6s\n', ...
        yn(FX.phaser), yn(FX.chorus), yn(FX.tremolo));
fprintf('  Delay:%-6s  Reverb:%-6s Looper:%-6s\n', ...
        yn(FX.delay), yn(FX.reverb), yn(FX.looper));
fprintf('---------------------------------------------------------------\n\n');

%% ===========================================================================
% STEP 1: TOOLCHAIN CHECK
% ===========================================================================
[tools_ok, iverilog_path, vvp_path, g_flag] = setup_check();
if ~tools_ok
    error(['ERROR: Icarus Verilog toolchain failed its compile-and-run check.\n' ...
           'Use Icarus version 10 or newer. See SIM/toolchain_check.log and FIX_README.md.']);
end

%% ===========================================================================
% STEP 2: PREPARE AUDIO (WAV -> PCM -> input_samples.txt)
% ===========================================================================
fprintf('STEP 1/6: Preparing Audio (WAV -> PCM)...\n');
[pcm_samples, Fs, num_samples, audio_meta] = prepare_audio(input_wav, input_txt, MAX_SECONDS);

%% ===========================================================================
% STEP 3: GENERATE sim_config.svh
% ===========================================================================
fprintf('STEP 2/6: Generating SIM/sim_config.svh...\n');

fid_cfg = fopen(sim_header, 'w');
if fid_cfg == -1
    error('ERROR: Cannot write to %s — check SIM folder exists.', sim_header);
end

fprintf(fid_cfg, '// AUTO-GENERATED by MATLAB run_pedalboard.m\n');
fprintf(fid_cfg, '// %s\n\n', datestr(now));
fprintf(fid_cfg, '`ifndef SIM_CONFIG_SVH\n');
fprintf(fid_cfg, '`define SIM_CONFIG_SVH\n\n');
fprintf(fid_cfg, '// Effect Enable Bits\n');
fprintf(fid_cfg, '`define CFG_ENABLE_PITCH       1''b%d\n', int32(FX.pitch));
fprintf(fid_cfg, '`define CFG_ENABLE_WAH         1''b%d\n', int32(FX.wah));
fprintf(fid_cfg, '`define CFG_ENABLE_DISTORTION  1''b%d\n', int32(FX.distortion));
fprintf(fid_cfg, '`define CFG_ENABLE_PHASER      1''b%d\n', int32(FX.phaser));
fprintf(fid_cfg, '`define CFG_ENABLE_CHORUS      1''b%d\n', int32(FX.chorus));
fprintf(fid_cfg, '`define CFG_ENABLE_TREMOLO     1''b%d\n', int32(FX.tremolo));
fprintf(fid_cfg, '`define CFG_ENABLE_DELAY       1''b%d\n', int32(FX.delay));
fprintf(fid_cfg, '`define CFG_ENABLE_REVERB      1''b%d\n', int32(FX.reverb));
fprintf(fid_cfg, '`define CFG_ENABLE_LOOPER      1''b%d\n\n', int32(FX.looper));
tail_samples = 0;
if (FX.delay || FX.reverb) && ~FX.looper
    tail_samples = round(TAIL_SECONDS * Fs);
end
fprintf(fid_cfg, '`define CFG_TAIL_SAMPLES %d\n', tail_samples);
expected_output_samples = num_samples + tail_samples;
fprintf('  Expected output: %.3f seconds, approximately %.3f MB (16-bit mono WAV).\n', ...
    expected_output_samples/Fs, (44 + 2*expected_output_samples)/1e6);
fprintf(fid_cfg, '// Effect Parameters\n');
fprintf(fid_cfg, '`define CFG_PITCH_MODE         %d\n', PITCH_MODE);
fprintf(fid_cfg, '`define CFG_DIST_DRIVE         16''d%d\n', DIST_DRIVE);
fprintf(fid_cfg, '`define CFG_DIST_THRESHOLD     16''d%d\n', DIST_THRESHOLD);
fprintf(fid_cfg, '`define CFG_DELAY_MS           %d\n', DELAY_MS);
fprintf(fid_cfg, '`define CFG_DELAY_WET          16''d%d\n', DELAY_WET);
fprintf(fid_cfg, '`define CFG_DELAY_FEEDBACK     16''d%d\n', DELAY_FEEDBACK);
fprintf(fid_cfg, '`define CFG_LOOP_MS            %d\n\n', LOOP_MS);
fprintf(fid_cfg, '`endif // SIM_CONFIG_SVH\n');
fclose(fid_cfg);
fprintf('  sim_config.svh generated.\n\n');

%% ===========================================================================
% STEP 4: COMPILE RTL (iverilog)
% ===========================================================================
fprintf('STEP 3/6: Compiling RTL with Icarus Verilog...\n');

% List all RTL source files (order matters: dependencies first)
rtl_files = {
    fullfile(rtl_dir, 'distortion.sv')
    fullfile(rtl_dir, 'delay_echo.sv')
    fullfile(rtl_dir, 'chorus.sv')
    fullfile(rtl_dir, 'tremolo.sv')
    fullfile(rtl_dir, 'wah.sv')
    fullfile(rtl_dir, 'phaser.sv')
    fullfile(rtl_dir, 'reverb.sv')
    fullfile(rtl_dir, 'pitch_shift.sv')
    fullfile(rtl_dir, 'looper.sv')
    fullfile(rtl_dir, 'pedalboard_top.sv')
    fullfile(tb_dir,  'tb_pedalboard.sv')
};

vvp_out = fullfile(sim_dir, 'pedalboard_sim.vvp');

% Build quoted file list for the shell command
file_args = '';
for k = 1:length(rtl_files)
    file_args = [file_args ' "' rtl_files{k} '"']; %#ok<AGROW>
end

if exist(vvp_out, 'file'), delete(vvp_out); end % Never accept stale build output

compile_cmd = sprintf('"%s" %s -s tb_pedalboard -I "%s" -o "%s" %s 2>&1', ...
    iverilog_path, g_flag, sim_dir, vvp_out, file_args);

fprintf('  Command: iverilog %s -I SIM/ -o SIM/pedalboard_sim.vvp [RTL/*.sv TB]\n', g_flag);
[compile_status, compile_out] = system(compile_cmd);
compile_log = fullfile(sim_dir, 'compile_log.txt');
fid_log = fopen(compile_log, 'w');
if fid_log ~= -1
    fprintf(fid_log, 'Command: %s\nExit code: %d\n%s\n', ...
        compile_cmd, compile_status, compile_out);
    fclose(fid_log);
end
if compile_status == -1073741819 || compile_status == 3221225477
    error('pedalboard:CompilerCrash', ...
        ['Icarus crashed with Windows access violation 0xC0000005.\n' ...
         'This is a compiler-process crash, not a MATLAB audio error.\n' ...
         'Reinstall/update Icarus and set ICARUS_BIN to the new bin folder.\n' ...
         'See %s and SIM/toolchain_check.log.'], compile_log);
end

if compile_status ~= 0 || ~isempty(strtrim(compile_out))
    fprintf('\n--- Compiler Output ---\n%s\n-----------------------\n', compile_out);
end

if compile_status ~= 0
    error(['ERROR: RTL compilation failed (exit code %d).\n' ...
           'Compiler output shown above.'], compile_status);
end

if ~exist(vvp_out, 'file')
    % Some iverilog versions return 0 but still fail (crash/internal error)
    error(['ERROR: Compilation appeared to succeed but pedalboard_sim.vvp was not created.\n' ...
           'This usually means Icarus Verilog crashed on a syntax it cannot handle.\n' ...
           'Compiler output: %s'], compile_out);
end

fprintf('  Compilation successful: pedalboard_sim.vvp\n\n');

%% ===========================================================================
% STEP 5: RUN SIMULATION (vvp) — from project root
% ===========================================================================
fprintf('STEP 4/6: Running RTL Simulation (vvp)...\n');

% Delete any stale output file
if exist(output_txt, 'file'), delete(output_txt); end

% vvp must be run from the project root so that relative file paths
% in tb_pedalboard.sv ("MATLAB/input_samples.txt") resolve correctly.
if ispc
    sim_script = fullfile(sim_dir, 'run_sim.bat');
    fid_sim = fopen(sim_script, 'w');
    fprintf(fid_sim, '@echo off\r\n');
    fprintf(fid_sim, 'cd /d "%s"\r\n', project_root);
    fprintf(fid_sim, '"%s" "SIM\\pedalboard_sim.vvp"\r\n', vvp_path);
    fclose(fid_sim);
    run_sim_cmd = sprintf('cmd /c "%s"', sim_script);
else
    sim_script = fullfile(sim_dir, 'run_sim.sh');
    fid_sim = fopen(sim_script, 'w');
    fprintf(fid_sim, '#!/bin/sh\n');
    fprintf(fid_sim, 'cd "%s"\n', project_root);
    fprintf(fid_sim, '"%s" "SIM/pedalboard_sim.vvp"\n', vvp_path);
    fclose(fid_sim);
    system(sprintf('chmod +x "%s"', sim_script));
    run_sim_cmd = sprintf('sh "%s"', sim_script);
end

fprintf('  Running simulation for %.2f seconds of audio plus %.2f seconds of tail...\n', num_samples/Fs, tail_samples/Fs);
tic;
[sim_status, sim_out] = system(run_sim_cmd);
sim_elapsed = toc;

% Always print simulation output (contains $display messages from RTL)
if ~isempty(strtrim(sim_out))
    fprintf('%s\n', sim_out);
end

if sim_status ~= 0
    error('ERROR: Simulation failed with exit code %d.', sim_status);
end

if ~exist(output_txt, 'file')
    error(['ERROR: Simulation completed but output_samples.txt was not created.\n' ...
           'Check simulation output above for error messages.']);
end

fprintf('  Simulation completed in %.1f seconds.\n\n', sim_elapsed);

%% ===========================================================================
% STEP 6: RECONSTRUCT AUDIO (PCM -> WAV)
% ===========================================================================
fprintf('STEP 5/6: Reconstructing Audio (PCM -> WAV)...\n');
[audio_out, ~] = reconstruct_audio(output_txt, output_wav, Fs, PLAY_AUDIO);

%% ===========================================================================
% STEP 7: VERIFY & PLOT
% ===========================================================================
fprintf('STEP 6/6: Verifying and Plotting...\n');
cfg_verify.TAIL_SAMPLES   = tail_samples;
cfg_verify.FX             = FX;
cfg_verify.DIST_THRESHOLD = DIST_THRESHOLD;
stats = verify_effects(input_txt, output_txt, cfg_verify);
stats.audio = audio_meta;
stats.input_file = input_wav;
stats.output_file = output_wav;
stats.output_duration = numel(audio_out)/Fs;
stats.tail_seconds = tail_samples/Fs;
output_info = dir(output_wav);
stats.output_bytes = output_info(1).bytes;

fprintf('===============================================================\n');
fprintf('COMPLETE!\n');
fprintf('  Input:  %s\n', input_wav);
fprintf('  Output: %s\n', output_wav);
fprintf('  Samples processed: %d (%.2f s @ %d Hz)\n', num_samples, num_samples/Fs, Fs);
fprintf('===============================================================\n');

end % function run_pedalboard


%% ===========================================================================
% HELPER: SHORT YES/NO STRING
% ===========================================================================
function s = yn(v)
    if v, s = 'ON'; else, s = 'off'; end
end


%% ===========================================================================
% HELPER: PARSE EFFECT SELECTION
% ===========================================================================
function FX = parse_effect_selection(FX, sel)
    % Clear all active flags first
    fnames = fieldnames(FX);
    for k = 1:length(fnames), FX.(fnames{k}) = false; end

    if isempty(sel), return; end

    if iscell(sel)
        for i = 1:length(sel), FX = activate_one(FX, sel{i}); end
        return;
    end

    if isnumeric(sel) && length(sel) > 1
        for i = 1:length(sel), FX = activate_one(FX, sel(i)); end
        return;
    end

    FX = activate_one(FX, sel);
end


function FX = activate_one(FX, item)
    if isstring(item) || ischar(item)
        name = lower(strtrim(char(item)));
        switch name
            case {'pitch', '0', 'octave'},   FX.pitch      = true;
            case {'wah',   '1', 'autowah'},   FX.wah        = true;
            case {'distortion','2','dist'},   FX.distortion = true;
            case {'phaser','3','phase'},      FX.phaser     = true;
            case {'chorus','4'},              FX.chorus     = true;
            case {'tremolo','5','trem'},      FX.tremolo    = true;
            case {'delay', '6','echo'},       FX.delay      = true;
            case {'reverb','7','verb'},       FX.reverb     = true;
            case {'looper','8','loop'},       FX.looper     = true;
            case {'bypass','-1','none','off','clean','dry'}
                % All remain false — bypass mode
            otherwise
                warning('run_pedalboard:UnknownEffect', ...
                        'Unknown effect "%s". Using bypass.', name);
        end
    elseif isnumeric(item)
        id = round(item);
        switch id
            case 0,  FX.pitch      = true;
            case 1,  FX.wah        = true;
            case 2,  FX.distortion = true;
            case 3,  FX.phaser     = true;
            case 4,  FX.chorus     = true;
            case 5,  FX.tremolo    = true;
            case 6,  FX.delay      = true;
            case 7,  FX.reverb     = true;
            case 8,  FX.looper     = true;
            case -1, % bypass — all remain false
            otherwise
                warning('run_pedalboard:UnknownEffectId', ...
                        'Unknown effect ID %d (valid: -1 to 8).', id);
        end
    end
end
