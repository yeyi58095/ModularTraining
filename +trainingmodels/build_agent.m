function agent = build_agent(spec,obsInfo,actInfo,device)
% Shared PPO builder. Profiles contain architecture and optimizer settings.
assert(strcmp(spec.algorithm,'PPO'),'Modular:Algorithm','This builder currently supports PPO only.');
assert(spec.sampleTime==0.1,'Modular:SampleTime','The current FAFA environment requires sampleTime=0.1.');
validateattributes(spec.lstmUnits,{'numeric'},{'scalar','integer','nonnegative'});
assert(isequal(obsInfo.Dimension,[10 1]) && isequal(actInfo.Dimension,[1 1]), ...
    'Modular:Environment','Profiles currently target the FAFA 10-observation, 1-action environment.');
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
criticLayers = [inputLayers(spec.lstmUnits,'lstm_value'); ...
    hiddenLayers(spec.criticHidden,'cv'); fullyConnectedLayer(1,'Name','value')];
critic = rlValueFunction(criticLayers,obsInfo,'UseDevice',device);
opts = rlPPOAgentOptions('SampleTime',spec.sampleTime,'DiscountFactor',spec.discountFactor, ...
    'MiniBatchSize',spec.miniBatchSize,'ExperienceHorizon',spec.experienceHorizon, ...
    'NumEpoch',spec.numEpoch,'EntropyLossWeight',spec.entropyLossWeight);
opts.ActorOptimizerOptions.LearnRate = spec.actorLearnRate;
opts.ActorOptimizerOptions.GradientThreshold = spec.actorGradientThreshold;
opts.CriticOptimizerOptions.LearnRate = spec.criticLearnRate;
opts.CriticOptimizerOptions.GradientThreshold = spec.criticGradientThreshold;
agent = rlPPOAgent(actor,critic,opts);
end

function layers = inputLayers(units,name)
if units > 0
    layers = [sequenceInputLayer(10,'Name','observation'); ...
        lstmLayer(units,'Name',name,'OutputMode','sequence', ...
        'InputWeightsInitializer','glorot','RecurrentWeightsInitializer','orthogonal')];
else
    layers = featureInputLayer(10,'Name','observation','Normalization','none');
end
end

function layers = hiddenLayers(widths,prefix)
validateattributes(widths,{'numeric'},{'vector','integer','positive','nonempty'});
layers = [];
for k=1:numel(widths)
    layers = [layers; fullyConnectedLayer(widths(k),'Name',sprintf('%s_fc%d',prefix,k)); ...
        reluLayer('Name',sprintf('%s_relu%d',prefix,k))]; %#ok<AGROW>
end
end
