function [actor,critics]=paper_sac_networks(spec,obs,act,device)
% Independent two-layer normalized MLPs; unbounded mean, positive std.
body=[featureInputLayer(10,'Normalization','none','Name','observation');hidden(spec.hiddenUnits)];
net=layerGraph(body);
net=addLayers(net,fullyConnectedLayer(1,'Name','mean','WeightsInitializer','glorot'));
net=addLayers(net,[fullyConnectedLayer(1,'Name','std_fc','WeightsInitializer','glorot');softplusLayer('Name','std')]);
net=connectLayers(net,'relu2','mean');net=connectLayers(net,'relu2','std_fc');
actor=rlContinuousGaussianActor(net,obs,act,'ObservationInputNames','observation', ...
    'ActionMeanOutputNames','mean','ActionStandardDeviationOutputNames','std','UseDevice',device);
for k=1:2
    net=layerGraph();
    net=addLayers(net,featureInputLayer(10,'Normalization','none','Name','observation'));
    net=addLayers(net,featureInputLayer(1,'Normalization','none','Name','action'));
    net=addLayers(net,[concatenationLayer(1,2,'Name','concat');hidden(spec.hiddenUnits); ...
        fullyConnectedLayer(1,'Name','q','WeightsInitializer','glorot')]);
    net=connectLayers(net,'observation','concat/in1');net=connectLayers(net,'action','concat/in2');
    q=rlQValueFunction(net,obs,act,'ObservationInputNames','observation','ActionInputNames','action','UseDevice',device);
    if k==1,critics=q;else,critics(k)=q;end %#ok<AGROW>
end
end
function layers=hidden(n)
layers=[fullyConnectedLayer(n,'Name','fc1','WeightsInitializer','glorot'); ...
    layerNormalizationLayer('Name','norm1');reluLayer('Name','relu1'); ...
    fullyConnectedLayer(n,'Name','fc2','WeightsInitializer','glorot'); ...
    layerNormalizationLayer('Name','norm2');reluLayer('Name','relu2')];
end
