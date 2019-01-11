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
I_BREATHING_RATE_EST_FFT = I_HEART_EST_PEAK_COUNT + sizeFLOAT;
I_BREATHING_RATE_EST_XCORR = I_BREATHING_RATE_EST_FFT + sizeFLOAT;
I_BREATHING_RATE_EST_PEAK_COUNT = I_BREATHING_RATE_EST_XCORR + sizeFLOAT;

I_MOTION_DETECTION_FLAG = I_BREATHING_RATE_EST_PEAK_COUNT + 8*sizeFLOAT;
I_RESERVED = I_MOTION_DETECTION_FLAG + sizeFLOAT;

%% Set Parameters
userPort = '/dev/ttyACM1';
userBaudRate = 115200;
dataPort = '/dev/ttyACM2';
dataBaudRate = 921600;
cfgFileName = 'xwr1642_profile_VitalSigns_20fps_Front.cfg';

%% Create Serial Objects
delete(instrfind);
user = serial(userPort,'BaudRate',userBaudRate);
data = serial(dataPort,'BaudRate',dataBaudRate);
data.InputBufferSize = 100000;

%% Reading Initializations
% Parameters
packetSize = I_MESSAGE_TLV_HEADER_2;               % Value large enough, doesn't matter how much
packet = zeros(I_MESSAGE_TLV_HEADER_2,1);   % Packet Initialization
xtime = 20;                     % Time in seconds to be displayed on the animated line
saveData = 1;                   % Save Data for offline Reading

if(saveData)
    maxSaveSize = 1000;
    nSaved = 1;
    timeV = zeros(1,maxSaveSize);
    phaseV = zeros(1,maxSaveSize);
    BreathV = zeros(1,maxSaveSize);
    HeartV = zeros(1,maxSaveSize);
    BreathRV = zeros(1,maxSaveSize);
    HeartRV = zeros(1,maxSaveSize);
end

% Plot Initialization
figure(1)
subplot(3,1,1)
title('Phase Unrwapped'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h1 = animatedline;
motionW = annotation('textbox', [0.92, 0.75, 0.1, 0.1]); 
                     
%figure(2)
subplot(3,1,2)
title('Filtered Breath Out'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h2 = animatedline;
bRateW = annotation('textbox', [0.92, 0.43, 0.1, 0.1]);

%figure(3)
subplot(3,1,3)
title('Filtered Hearth Out'),xlabel('t'),ylabel('phase')
xlim([0 xtime]);
h3 = animatedline;
hRateW = annotation('textbox', [0.92, 0.12, 0.1, 0.1]);

Stop = uicontrol('Style', 'PushButton', ...
                         'String', 'Stop Sensor', ...
                         'Callback', @pushStopPressed,...
                         'DeleteFcn', 'delete(gcbf)');
Clear = uicontrol('Style', 'PushButton', ...
                         'String', 'Clear points', ...
                         'Callback', {@pushClearPressed,h1},...
                         'Position',[100 20 60 20],...
                         'DeleteFcn', 'delete(gcbf)'); 
                     
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

%% Initiate Reading
fopen(data);
flushinput(data);
if(saveData)
    %% Save Data Cycle
    tDisplay = tic;
    tSave = tic;
    while(1)
        if(stopB)
            StopSensor(data,user);
            break;
        end        
        
        b = fread(data,1,'uint8');      % Read Byte

        if(b == MW(mwcount))  % Check for MAGIC_WORD        
            mwcount = mwcount + 1;
            if(mwcount == MAGIC_WORD + 1)         % MAGIC_WORD found: init package read
                mwcount = 1;
                for n = (MAGIC_WORD + 1):(packetSize)            % Read packetSize - MAGIC_WORD bytes
                    packet(n) = fread(data,1,'char');                
                end             
                t = toc(tDisplay);
                tS = toc(tSave);
                if(t > xtime)
                    tDisplay = tic;
                    t = toc(tDisplay);
                    clearpoints(h1);
                    clearpoints(h2);
                    clearpoints(h3);
                    if(data.BytesAvailable == data.InputBufferSize)
                        flushinput(data);
                    end
                end                                                
                phase = double(typecast(swapbytes(uint8(packet(I_UNWRAP_PHASE_PEAK_MM:(I_OUTPUT_FILTER_BREATH_OUT - 1)))),'single'));
                breath = double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_BREATH_OUT:(I_OUTPUT_FILTER_HEARTH_OUT - 1)))),'single'));
                heart = double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_HEARTH_OUT:(I_HEART_RATE_EST_FFT - 1)))),'single'));
                motion = typecast(swapbytes(uint8(packet(I_MOTION_DETECTION_FLAG:(I_RESERVED - 1)))),'single');
                bRate = typecast(swapbytes(uint8(packet(I_BREATHING_RATE_EST_FFT:(I_BREATHING_RATE_EST_XCORR - 1)))),'single');
                hRate = typecast(swapbytes(uint8(packet(I_HEART_RATE_EST_FFT:(I_HEART_RATE_EST_FFT_4HZ - 1)))),'single');
                
                addpoints(h1,t,phase);
                addpoints(h2,t,breath);
                addpoints(h3,t,heart);
                
                motionW.String = num2str(motion);           
                bRateW.String = num2str(bRate,3);
                hRateW.String = num2str(hRate,3);
                drawnow
                
                timeV(nSaved) = tS;
                phaseV(nSaved) = phase;
                BreathV(nSaved) = breath;
                HeartV(nSaved) = heart;
                BreathRV(nSaved) = bRate;
                HeartRV(nSaved) = hRate;
                
                nSaved = nSaved + 1;
                
                if(nSaved == maxSaveSize + 1)
                    stopB = 1;
                end
                
                disp(data.BytesAvailable);
            end
        else
            mwcount = 1;
        end   
    end
    
    save('VitalSignsData.mat', 'timeV', 'phaseV', 'BreathV', 'HeartV', 'BreathRV', 'HeartRV');
    
else
    %% Don 't Save Data Cycle
    tic
    while(1)  
        if(stopB)
            StopSensor(data,user);
            break;
        end
        
        b = fread(data,1,'uint8');      % Read Byte

        if(b == MW(mwcount))  % Check for MAGIC_WORD        
            mwcount = mwcount + 1;
            if(mwcount == MAGIC_WORD + 1)         % MAGIC_WORD found: init package read
                mwcount = 1;
                for n = (MAGIC_WORD + 1):(packetSize)            % Read packetSize - MAGIC_WORD bytes
                    packet(n) = fread(data,1,'char');                
                end             
                t = toc;
                if(t > xtime)
                    tic
                    t = toc;
                    clearpoints(h1);
                    clearpoints(h2);
                    clearpoints(h3);
                    
                    if(data.BytesAvailable == data.InputBufferSize)
                        flushinput(data);
                    end
                end                                                
                addpoints(h1,t,double(typecast(swapbytes(uint8(packet(I_UNWRAP_PHASE_PEAK_MM:(I_OUTPUT_FILTER_BREATH_OUT - 1)))),'single')));
                addpoints(h2,t,double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_BREATH_OUT:(I_OUTPUT_FILTER_HEARTH_OUT - 1)))),'single')));
                addpoints(h3,t,double(typecast(swapbytes(uint8(packet(I_OUTPUT_FILTER_HEARTH_OUT:(I_HEART_RATE_EST_FFT - 1)))),'single')));
                
                motionW.String = num2str(typecast(swapbytes(uint8(packet(I_MOTION_DETECTION_FLAG:(I_RESERVED - 1)))),'single'));           
                bRateW.String = num2str(typecast(swapbytes(uint8(packet(I_BREATHING_RATE_EST_FFT:(I_BREATHING_RATE_EST_XCORR - 1)))),'single'),3);
                hRateW.String = num2str(typecast(swapbytes(uint8(packet(I_HEART_RATE_EST_FFT:(I_HEART_RATE_EST_FFT_4HZ - 1)))),'single'),3);
                drawnow
            end
        else
            mwcount = 1;
        end   
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