function agent = build_agent(spec,obsInfo,actInfo,device)
% PPO 建構器：將 spec 轉成 Gaussian actor、value critic 與 optimizer 設定。
% 輸入 spec、觀測／動作規格及裝置，回傳新 agent；此函式不載入 checkpoint 或開始 train。
% Shared PPO builder. Profiles contain architecture and optimizer settings.
assert(strcmp(spec.algorithm,'PPO'),'Modular:Algorithm','This builder currently supports PPO only.');
assert(spec.sampleTime==0.1,'Modular:SampleTime','The current FAFA environment requires sampleTime=0.1.');
validateattributes(spec.lstmUnits,{'numeric'},{'scalar','integer','nonnegative'});
assert(isequal(obsInfo.Dimension,[10 1]) && isequal(actInfo.Dimension,[1 1]), ...
    'Modular:Environment','Profiles currently target the FAFA 10-observation, 1-action environment.');
% actor 主幹後分成 mean 與 std；mean 以 tanh 限幅，std 以 softplus 保持正值。
actorLayers = inputLayers(spec.lstmUnits,'lstm_memory');
actorLayers = [actorLayers; hiddenLayers(spec.actorHidden,'ip')];
actorLayers = [actorLayers; fullyConnectedLayer(1,'Name','ip_out')];
meanLayers = [hiddenLayers(spec.meanHidden,'mp'); fullyConnectedLayer(1,'Name','mp_final'); ...
    tanhLayer('Name','tanh'); scalingLayer('Name','mp_out','Scale',actInfo.UpperLimit)];
stdLayers = [hiddenLayers(spec.stdHidden,'vp'); fullyConnectedLayer(1,'Name','vp_final'); ...
    softplusLayer('Name','sdev')];
net = layerGraph(actorLayers);
net = addLayers(net,meanLayers);
net = addLayers(net,stdLayers);
net = connectLayers(net,'ip_out',meanLayers(1).Name);
net = connectLayers(net,'ip_out',stdLayers(1).Name);
actor = rlContinuousGaussianActor(net,obsInfo,actInfo, ...
    'ObservationInputNames','observation','ActionMeanOutputNames','mp_out', ...
    'ActionStandardDeviationOutputNames','sdev','UseDevice',device);
% critic 使用自己的網路參數，不與 actor 共享可學習權重。
criticLayers = [inputLayers(spec.lstmUnits,'lstm_value'); ...
    hiddenLayers(spec.criticHidden,'cv'); fullyConnectedLayer(1,'Name','value')];
critic = rlValueFunction(criticLayers,obsInfo,'UseDevice',device);
% 把資料式 profile 套入實際 PPO 與 optimizer；spec 只是設定，不是 agent 本身。
opts = rlPPOAgentOptions('SampleTime',spec.sampleTime,'DiscountFactor',spec.discountFactor, ...
    'MiniBatchSize',spec.miniBatchSize,'ExperienceHorizon',spec.experienceHorizon, ...
    'NumEpoch',spec.numEpoch,'EntropyLossWeight',spec.entropyLossWeight);
% Actor LearnRate 影響策略更新；Critic LearnRate 影響價值估計，兩者獨立設定。
opts.ActorOptimizerOptions.LearnRate = spec.actorLearnRate;
opts.ActorOptimizerOptions.GradientThreshold = spec.actorGradientThreshold;
opts.CriticOptimizerOptions.LearnRate = spec.criticLearnRate;
opts.CriticOptimizerOptions.GradientThreshold = spec.criticGradientThreshold;
agent = rlPPOAgent(actor,critic,opts);
end

function layers = inputLayers(units,name)
% lstmUnits>0 使用 sequenceInput 與 LSTM；為 0 時改用前饋 featureInput。
if units > 0
    layers = [sequenceInputLayer(10,'Name','observation'); ...
        % OutputMode=sequence 保留每個時間步的輸出，讓 actor／critic 使用序列記憶。
        lstmLayer(units,'Name',name,'OutputMode','sequence', ...
        'InputWeightsInitializer','glorot','RecurrentWeightsInitializer','orthogonal')];
else
    layers = featureInputLayer(10,'Name','observation','Normalization','none');
end
end

function layers = hiddenLayers(widths,prefix)
% 按 widths 依序組合 fullyConnected／ReLU 層，以 prefix 命名。
validateattributes(widths,{'numeric'},{'vector','integer','positive','nonempty'});
layers = [];
for k=1:numel(widths)
    layers = [layers; fullyConnectedLayer(widths(k),'Name',sprintf('%s_fc%d',prefix,k)); ...
        reluLayer('Name',sprintf('%s_relu%d',prefix,k))]; %#ok<AGROW>
end
end
