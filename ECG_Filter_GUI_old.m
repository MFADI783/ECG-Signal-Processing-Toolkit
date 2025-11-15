function ECG_Filter_GUI
    % Main GUI function
    clc; clear; close all;
    
    % ======================== GUI SETUP ========================
    fig = uifigure('Name', 'ECG Filter GUI', 'Position', [100 100 1000 650]);
    
    % Create handles structure
    handles = struct();
    handles.fig = fig;
    handles.Fs = 500;  % Default sampling rate
    
    % Axes for plotting
    handles.ax1 = uiaxes(fig, 'Position', [50 350 400 250]);
    handles.ax1.Title.String = 'Original ECG';
    handles.ax1.XLabel.String = 'Time (s)';
    handles.ax1.YLabel.String = 'Amplitude (mV)';
    grid(handles.ax1, 'on');
    
    handles.ax2 = uiaxes(fig, 'Position', [525 350 400 250]);
    handles.ax2.Title.String = 'Filtered ECG';
    handles.ax2.XLabel.String = 'Time (s)';
    handles.ax2.YLabel.String = 'Amplitude (mV)';
    grid(handles.ax2, 'on');
    
    handles.ax3 = uiaxes(fig, 'Position', [50 50 400 250]);
    handles.ax3.Title.String = 'Frequency Spectrum';
    handles.ax3.XLabel.String = 'Frequency (Hz)';
    handles.ax3.YLabel.String = 'Magnitude (dB)';
    grid(handles.ax3, 'on');
    
    handles.ax4 = uiaxes(fig, 'Position', [525 50 400 250]);
    handles.ax4.Title.String = 'Spectrogram';
    handles.ax4.XLabel.String = 'Time (s)';
    handles.ax4.YLabel.String = 'Frequency (Hz)';
    
    % Control Panel
    panel = uipanel(fig, 'Title', 'Controls', 'Position', [875 50 100 550]);
    
    % File format selection
    uilabel(panel, 'Position', [10 500 80 22], 'Text', 'File Format:');
    handles.formatDrop = uidropdown(panel, 'Position', [10 475 80 22], ...
        'Items', {'Auto', 'MATLAB', 'Text', 'Binary'}, 'Value', 'Auto');
    
    % Filter selection
    uilabel(panel, 'Position', [10 425 80 22], 'Text', 'Filter Type:');
    handles.filterDrop = uidropdown(panel, 'Position', [10 400 80 22], ...
        'Items', {'High-Pass', 'Low-Pass', 'Bandstop'}, 'Value', 'High-Pass');
    
    % Sampling rate input
    uilabel(panel, 'Position', [10 350 80 22], 'Text', 'Fs (Hz):');
    handles.FsEdit = uieditfield(panel, 'numeric', ...
        'Position', [10 325 80 22], 'Value', 500);
    
    % Buttons
    uibutton(panel, 'Text', 'Load ECG', 'Position', [10 275 80 30], ...
        'ButtonPushedFcn', @(btn,event) loadECG(handles));
    uibutton(panel, 'Text', 'Apply Filter', 'Position', [10 225 80 30], ...
        'ButtonPushedFcn', @(btn,event) applyFilter(handles));
    uibutton(panel, 'Text', 'Reset', 'Position', [10 175 80 30], ...
        'ButtonPushedFcn', @(btn,event) resetAll(handles));
    
    % Metrics display
    uilabel(panel, 'Position', [10 125 80 22], 'Text', 'Metrics:');
    handles.snrLabel = uilabel(panel, 'Position', [10 100 80 22], 'Text', 'SNR: -- dB');
    handles.mseLabel = uilabel(panel, 'Position', [10 75 80 22], 'Text', 'MSE: --');
    handles.hrLabel = uilabel(panel, 'Position', [10 50 80 22], 'Text', 'HR: -- bpm');
    
    % Status message
    handles.statusLabel = uilabel(fig, 'Position', [50 610 400 22], 'Text', 'Ready to load ECG signal...');
    
    % Store handles
    guidata(fig, handles);
end

% ======================== CORE FUNCTIONS ========================

function loadECG(handles)
    handles = guidata(handles.fig);
    handles.statusLabel.Text = 'Loading ECG signal...';
    drawnow;
    
    try
        % Get current settings
        handles.Fs = handles.FsEdit.Value;
        if handles.Fs <= 0
            error('Sampling rate must be positive');
        end
        
        % File selection
        [file, path] = uigetfile({'*.*', 'All Files'}, 'Select ECG File');
        if isequal(file, 0)
            handles.statusLabel.Text = 'Load canceled';
            return;
        end
        
        % Load based on selected format
        switch handles.formatDrop.Value
            case 'MATLAB'
                data = load(fullfile(path, file));
                ecg = data.(char(fieldnames(data)));
            otherwise
                ecg = robustLoad(fullfile(path, file));
        end
        
        % Validate signal
        ecg = ecg(:); % Ensure column vector
        if ~isnumeric(ecg) || ~isvector(ecg)
            error('Invalid ECG data format');
        end
        
        % Store data
        handles.raw_signal = ecg;
        handles.statusLabel.Text = sprintf('Loaded: %s (%.1f sec)', file, length(ecg)/handles.Fs);
        
        % Plot original signal
        t = (0:length(ecg)-1)/handles.Fs;
        plot(handles.ax1, t, ecg);
        title(handles.ax1, sprintf('Original ECG: %s', file), 'Interpreter', 'none');
        grid(handles.ax1, 'on');
        
        % Plot initial FFT
        plotFFT(handles.ax3, ecg, handles.Fs, 'Original Spectrum');
        
    catch ME
        handles.statusLabel.Text = sprintf('Error: %s', ME.message);
        uialert(handles.fig, ME.message, 'Load Error');
    end
    
    guidata(handles.fig, handles);
end

function applyFilter(handles)
    handles = guidata(handles.fig);
    
    if ~isfield(handles, 'raw_signal') || isempty(handles.raw_signal)
        handles.statusLabel.Text = 'No ECG loaded!';
        uialert(handles.fig, 'Please load an ECG signal first', 'Filter Error');
        return;
    end
    
    try
        ecg = handles.raw_signal;
        Fs = handles.Fs;
        handles.statusLabel.Text = 'Applying filter...';
        drawnow;
        
        % Design filter
        switch handles.filterDrop.Value
            case 'High-Pass'
                [b,a] = cheby2(6, 40, 0.5/(Fs/2), 'high');
                fname = 'High-Pass (0.5Hz)';
            case 'Low-Pass'
                [b,a] = cheby2(6, 40, 40/(Fs/2), 'low');
                fname = 'Low-Pass (40Hz)';
            case 'Bandstop'
                [b,a] = cheby2(4, 40, [48 52]/(Fs/2), 'stop');
                fname = 'Bandstop (50Hz)';
        end
        
        % Apply zero-phase filtering
        filtered_ecg = filtfilt(b, a, ecg);
        handles.filtered_signal = filtered_ecg;
        
        % Plot results
        t = (0:length(ecg)-1)/Fs;
        
        % Time domain
        plot(handles.ax2, t, filtered_ecg);
        title(handles.ax2, sprintf('Filtered: %s', fname));
        grid(handles.ax2, 'on');
        
        % Frequency domain
        plotFFT(handles.ax3, filtered_ecg, Fs, 'Filtered Spectrum');
        legend(handles.ax3, 'Original', 'Filtered');
        
        % Corrected Spectrogram - using proper syntax
        [~,F,T,P] = spectrogram(filtered_ecg, 256, 250, 512, Fs);
        surf(handles.ax4, T, F, 10*log10(abs(P)), 'EdgeColor', 'none');
        view(handles.ax4, 2);
        axis(handles.ax4, 'tight');
        xlabel(handles.ax4, 'Time (s)');
        ylabel(handles.ax4, 'Frequency (Hz)');
        title(handles.ax4, 'Spectrogram');
        colorbar(handles.ax4);
        
        % Calculate metrics
        [SNR, MSE] = calculateMetrics(ecg, filtered_ecg);
        HR = estimateHeartRate(filtered_ecg, Fs);
        
        % Update metrics
        handles.snrLabel.Text = sprintf('SNR: %.2f dB', SNR);
        handles.mseLabel.Text = sprintf('MSE: %.4f', MSE);
        handles.hrLabel.Text = sprintf('HR: %.1f bpm', HR);
        
        handles.statusLabel.Text = sprintf('Applied %s filter', fname);
        
    catch ME
        handles.statusLabel.Text = sprintf('Filter Error: %s', ME.message);
        uialert(handles.fig, ME.message, 'Filter Error');
    end
    
    guidata(handles.fig, handles);
end

function resetAll(handles)
    handles = guidata(handles.fig);
    
    % Clear axes
    cla(handles.ax1); cla(handles.ax2); cla(handles.ax3); cla(handles.ax4);
    
    % Reset titles
    title(handles.ax1, 'Original ECG');
    title(handles.ax2, 'Filtered ECG');
    title(handles.ax3, 'Frequency Spectrum');
    title(handles.ax4, 'Spectrogram');
    
    % Clear data
    if isfield(handles, 'raw_signal')
        handles = rmfield(handles, 'raw_signal');
    end
    if isfield(handles, 'filtered_signal')
        handles = rmfield(handles, 'filtered_signal');
    end
    
    % Reset metrics
    handles.snrLabel.Text = 'SNR: -- dB';
    handles.mseLabel.Text = 'MSE: --';
    handles.hrLabel.Text = 'HR: -- bpm';
    
    handles.statusLabel.Text = 'System reset. Ready to load new ECG.';
    guidata(handles.fig, handles);
end

% ======================== HELPER FUNCTIONS ========================

function plotFFT(ax, signal, Fs, plotTitle)
    N = length(signal);
    f = Fs*(0:N/2-1)/N;
    fft_sig = abs(fft(signal))/N;
    plot(ax, f, 20*log10(fft_sig(1:N/2)));
    title(ax, plotTitle);
    grid(ax, 'on');
end

function [SNR, MSE] = calculateMetrics(original, filtered)
    signalPower = var(original);
    noisePower = var(original - filtered);
    SNR = 10*log10(signalPower / noisePower);
    MSE = mean((original - filtered).^2);
end

function HR = estimateHeartRate(signal, Fs)
    % Bandpass filter for QRS detection (5-15Hz)
    [b,a] = butter(4, [5 15]/(Fs/2));
    filtered = filtfilt(b, a, signal);
    
    % Squaring and moving average
    squared = filtered.^2;
    avg_window = ones(round(0.15*Fs),1)/round(0.15*Fs);
    smoothed = conv(squared, avg_window, 'same');
    
    % Peak detection
    [pks,locs] = findpeaks(smoothed, 'MinPeakHeight', 0.5*max(smoothed),...
                       'MinPeakDistance', 0.3*Fs);
    
    if length(locs) < 2
        HR = 0;
    else
        RR_intervals = diff(locs)/Fs;
        HR = 60/mean(RR_intervals);
    end
end

function data = robustLoad(filename)
    % Try multiple loading methods
    try
        % First try standard import
        temp = importdata(filename);
        if isstruct(temp)
            if isfield(temp, 'data')
                data = temp.data;
            else
                data = temp.(char(fieldnames(temp)));
            end
        else
            data = temp;
        end
        
        % If still not numeric, try other methods
        if ~isnumeric(data)
            try
                data = dlmread(filename);
            catch
                fid = fopen(filename, 'r');
                data = textscan(fid, '%f');
                fclose(fid);
                data = data{1};
            end
        end
    catch
        % Final fallback - read raw binary
        fid = fopen(filename, 'r');
        data = fread(fid, 'double');
        fclose(fid);
    end
    
    % Ensure column vector
    data = data(:);
end