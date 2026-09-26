function [ok, iverilog_path, vvp_path, g_flag] = setup_check()
% Check a modern Icarus installation by compiling AND running SystemVerilog.
% Optional override (folder containing both executables):
%   setenv('ICARUS_BIN', 'C:\iverilog\bin')
    ok = false;
    iverilog_path = '';
    vvp_path = '';
    g_flag = '-g2012';
    fprintf('Checking Icarus Verilog (project requires version 10 or newer)...\n');
    override = getenv('ICARUS_BIN');
    if ispc
        iv_name = 'iverilog.exe'; vv_name = 'vvp.exe';
        locator = 'where iverilog.exe';
    else
        iv_name = 'iverilog'; vv_name = 'vvp';
        locator = 'command -v iverilog';
    end
    candidates = {};
    if ~isempty(override)
        candidates = {override}; % An explicit override must not silently fall back.
    else
        [status, found] = system([locator ' 2>&1']);
        if status == 0
            lines = regexp(strtrim(found), '\r?\n', 'split');
            for k = 1:numel(lines)
                candidates{end+1} = fileparts(strtrim(lines{k})); %#ok<AGROW>
            end
        end
        candidates = [candidates, {'C:\iverilog\bin', ...
            'C:\Program Files\iverilog\bin', ...
            'C:\Program Files (x86)\iverilog\bin', ...
            'C:\tools\iverilog\bin', '/usr/local/bin', ...
            '/opt/homebrew/bin', '/usr/bin'}];
    end
    project_root = fileparts(fileparts(mfilename('fullpath')));
    log_path = fullfile(project_root, 'SIM', 'toolchain_check.log');
    log_text = '';
    probe_dir = tempname;
    mkdir(probe_dir);
    cleanup = onCleanup(@() rmdir(probe_dir, 's')); %#ok<NASGU>
    probe_sv = fullfile(probe_dir, 'probe.sv');
    probe_vvp = fullfile(probe_dir, 'probe.vvp');
    fid = fopen(probe_sv, 'w');
    if fid == -1, error('Cannot create compiler probe in %s', probe_dir); end
    fprintf(fid, ['module probe;\n' ...
        'logic signed [15:0] mem [0:3];\n' ...
        'initial begin mem[0] = -123; #1;\n' ...
        'if (mem[0] !== -123) $fatal(1, "probe failed");\n' ...
        '$display("PEDALBOARD_TOOLCHAIN_OK"); $finish; end\nendmodule\n']);
    fclose(fid);
    for k = 1:numel(candidates)
        iv = fullfile(candidates{k}, iv_name);
        vv = fullfile(candidates{k}, vv_name);
        if ~isfile(iv) || ~isfile(vv), continue; end
        [status, version] = system(sprintf('"%s" -V 2>&1', iv));
        log_text = [log_text sprintf('\nCompiler: %s\n%s\n', iv, version)]; %#ok<AGROW>
        major = regexp(version, 'Icarus Verilog version\s+(\d+)', 'tokens', 'once');
        if status ~= 0 || isempty(major) || str2double(major{1}) < 10
            log_text = [log_text 'Rejected: failed version check or version < 10.' newline]; %#ok<AGROW>
            continue;
        end
        if isfile(probe_vvp), delete(probe_vvp); end
        [status, output] = system(sprintf( ...
            '"%s" -g2012 -s probe -o "%s" "%s" 2>&1', iv, probe_vvp, probe_sv));
        log_text = [log_text sprintf('Compile status %d\n%s\n', status, output)]; %#ok<AGROW>
        if status ~= 0 || ~isfile(probe_vvp), continue; end
        [status, output] = system(sprintf('"%s" "%s" 2>&1', vv, probe_vvp));
        log_text = [log_text sprintf('Run status %d\n%s\n', status, output)]; %#ok<AGROW>
        if status == 0 && contains(output, 'PEDALBOARD_TOOLCHAIN_OK')
            ok = true; iverilog_path = iv; vvp_path = vv;
            fprintf('  Compiler: %s\n  Simulator: %s\n', iv, vv);
            fprintf('  [OK] SystemVerilog compile-and-run check passed (-g2012).\n');
            break;
        end
    end
    fid = fopen(log_path, 'w');
    if fid ~= -1, fprintf(fid, '%s', log_text); fclose(fid); end
    if ~ok
        fprintf(2, ['No working Icarus version 10+ pair was found.\n' ...
            'Install a modern Icarus build, restart MATLAB, and run setup_check.\n' ...
            'If needed, set ICARUS_BIN to its bin folder (both iverilog and vvp).\n' ...
            'Diagnostics: %s\n'], log_path);
    end
end
