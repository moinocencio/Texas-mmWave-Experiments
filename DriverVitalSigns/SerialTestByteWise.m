%% Connect to EVM 1642
close all
clear all
clc

%% Data Sizes
sizeUINT16 = 2;                  % Size of uint16 in bytes
sizeFLOAT = 4;                   % Size of float in bytes
MAGIC_WORD = 8;                  % Size of MAGIGWORD in bytes
HEADER = 40;                     % Size of HEADER 
MESSAGE_TLV_HEADER = 8;          % Size of MESSAGE_TLV 
VITAL_SIGNS_OUTPUT_STATS = 128;  % Size of OUTPUT_STATS
MW = typecast(uint16([258;772;1286;1800]),'uint8');       % Magic Word

%% Index
% Structure Index
I_HEADER = 1;                               
I_MESSAGE_TLV_HEADER_1 = I_HEADER + HEADER;
I_VITAL_SIGNS_OUTPUT_STATS = I_MESSAGE_TLV_HEADER_1 + MESSAGE_TLV_HEADER;
I_MESSAGE_TLV_HEADER_2 = I_VITAL_SIGNS_OUTPUT_STATS + VITAL_SIGNS_OUTPUT_STATS;
I_RANGE_PROFILE = I_MESSAGE_TLV_HEADER_2 + MESSAGE_TLV_HEADER;

% Output stats Index
I_RANGE_BIN_INDEX_MAX = I_VITAL_SIGNS_OUTPUT_STATS;
I_RANGE_BIN_INDEX_PHASE = I_RANGE_BIN_INDEX_MAX + sizeUINT16;
I_MAX_VAL = I_RANGE_BIN_INDEX_PHASE + sizeUINT16;
I_PROCESSING_CYCLES_OUT = I_MAX_VAL + sizeFLOAT;
I_RANGE_BIN_START_INDEX = I_PROCESSING_CYCLES_OUT + sizeFLOAT;
I_RANGE_BIN_END_INDEX = I_RANGE_BIN_START_INDEX + sizeUINT16;
I_UNWRAP_PHASE_PEAK_MM = I_RANGE_BIN_END_INDEX + sizeUINT16;
I_OUTPUT_FILTER_BREATH_OUT = I_UNWRAP_PHASE_PEAK_MM + sizeFLOAT;
I_OUTPUT_FILTER_HEARTH_OUT = I_OUTPUT_FILTER_BREATH_OUT + sizeFLOAT;
I_HEART_RATE_EST_FFT = I_OUTPUT_FILTER_HEARTH_OUT + sizeFLOAT;
I_HEART_RATE_EST_FFT_4HZ = I_HEART_RATE_EST_FFT + sizeFLOAT;
I_HEART_EST_XCORR = I_HEART_RATE_EST_FFT_4HZ + sizeFLOAT;
I_HEART_EST_PEAK_COUNT = I_HEART_EST_XCORR + sizeFLOAT;

I_MOTION_DETECTION_FLAG = I_MESSAGE_TLV_HEADER_2 - 2*sizeFLOAT - 1;

%% Set Parameters
userPort = 'COM5';
userBaudRate = 115200;
dataPort = 'COM6';
dataBaudRate = 921600;
cfgFileName = 'xwr1642_profile_VitalSigns_20fps_Front.cfg';

%% Create Serial Objects
delete(instrfind);
user = serial(userPort,'BaudRate',userBaudRate);
data = serial(dataPort,'BaudRate',dataBaudRate);
data.InputBufferSize = 50000;

%% Reading Initializations
% numRangeBinProcessed = rangeEnd_Index - rangeStart_Index + 1;
% Parameters
packetSize = 300;               % Value large enough, doesn't matter how much
packet = zeros(packetSize,1);   % Packet Initialization
xtime = 20;                     % Time in seconds to be displayed on the animated line

% Plot Initialization
figure(1)
subplot(3,1,1)
title('Phase Unrwapped'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h1 = animatedline;
Stop = uicontrol('Style', 'PushButton', ...
                         'String', 'Stop Sensor', ...
                         'Callback', @pushStopPressed,...
                         'DeleteFcn', 'delete(gcbf)');
Clear = uicontrol('Style', 'PushButton', ...
                         'String', 'Clear points', ...
                         'Callback', {@pushClearPressed,h1},...
                         'Position',[100 20 60 20],...
                         'DeleteFcn', 'delete(gcbf)');  
                     
%figure(2)
subplot(3,1,2)
title('Filtered Breath Out'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h2 = animatedline;

%figure(3)
subplot(3,1,3)
title('Filtered Hearth Out'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h3 = animatedline;

global stopB
stopB = 0;

% Sequence
mwcount = 1;                    % Magic Word Count
count = 1;                      % Packet index
axiscount = 1;                  % Axis refresh count

%% Load Configuration File
cfgFile = fileread(cfgFileName);
nLines = 1 + sum(cfgFile == newline);   % Number of lines of configuration file
confL = strings(1,nLines);

il = 1;
for ic = 1:length(cfgFile)
    tc = cfgFile(ic);
    if(tc == newline)
        il = il + 1;
    else 
        confL(il) = confL(il) + tc;
    end
end

%% Write Configuration File
fopen(user);
for i = 1:nLines
    fwrite(user,confL(i));
    pause(0.5);
end
fclose(user);
testHeader = zeros(1,40);

%% Initiate Reading
fopen(data);
tic
while(1)  
    if(stopB)
        StopSensor(data,user);
        break;
    end
    
    t = fread(data,1,'uint8');
    
    if(t == MW(mwcount))  % Check for MAGIC_WORD        
        mwcount = mwcount + 1;
        if(mwcount == MAGIC_WORD + 1)                       % MAGIC_WORD found: init package read
            mwcount = 1;
            for n = 9:(I_MESSAGE_TLV_HEADER_2+8)            % Read I_MESSAGE_TLV_HEADER_2 bytes
                if(stopB)                    
                    StopSensor(data,user);
                    break;
                end
                packet(n) = fread(data,1,'char');                
            end
            axiscount = axiscount + 1;              
            t = toc;
            if(t > xtime)
                tic
                t = toc;
                clearpoints(h1);
                clearpoints(h2);
                clearpoints(h3);
            end
            phase = double(typecast(swapbytes(uint8(packet(I_UNWRAP_PHASE_PEAK_MM:(I_OUTPUT_FILTER_BREATH_OUT - 1)))),'single'));
            breath = double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_BREATH_OUT:(I_OUTPUT_FILTER_HEARTH_OUT - 1)))),'single'));
            heart = double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_HEARTH_OUT:(I_HEART_RATE_EST_FFT - 1)))),'single'));
            disp(double(typecast(swapbytes(uint8(packet(I_HEART_RATE_EST_FFT:(I_HEART_RATE_EST_FFT_4HZ - 1)))),'single')));
            addpoints(h1,t,phase);
            addpoints(h2,t,breath);
            addpoints(h3,t,heart);
            drawnow
        end
    else
        mwcount = 1;
    end   
end


%% Functions
function pushClearPressed(~,~,h1)
    disp('Points Cleared');
    clearpoints(h1);
end

function pushStopPressed(~,~)    
    global stopB
    stopB = 1;
end

function StopSensor(data,user)
    fclose(data);
    stopL = "sensorStop" + newline;
    fopen(user);
    fwrite(user,stopL);
    pause(0.5);
    fclose(user);
    disp('Sensor Stopped');
end