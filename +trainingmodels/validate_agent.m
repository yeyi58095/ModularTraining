function validate_agent(agent,spec)
% 模型相容性檢查：確認 PPO 類型、LSTM／隱藏層大小與主要學習設定符合 spec。
% 不修改權重；檢查失敗拋出對應錯誤，避免用錯模型或學習參數續訓。
% Prevent a checkpoint with a different architecture from silently resuming.
assert(isa(agent,'rl.agent.rlPPOAgent'),'Modular:AgentType','Expected a PPO checkpoint.');
a = getModel(getActor(agent)); c = getModel(getCritic(agent));
if isfield(spec,'explorationStdScale')
    idx=find(strcmp({a.Layers.Name},'sdev'));
    assert(isscalar(idx) && isa(a.Layers(idx),class(scalingLayer)) && ...
        isequal(a.Layers(idx).Scale,spec.explorationStdScale), ...
        'Modular:StdScale','Checkpoint std scale differs from model specification.');
end
checkLayers(a.Layers,spec.lstmUnits,[spec.actorHidden(:)' 1 spec.meanHidden(:)' 1 spec.stdHidden(:)' 1]);
checkLayers(c.Layers,spec.lstmUnits,[spec.criticHidden(:)' 1]);
checkNamed(a.Layers,'ip',spec.actorHidden);
checkNamed(a.Layers,'mp',spec.meanHidden);
checkNamed(a.Layers,'vp',spec.stdHidden);
checkNamed(c.Layers,'cv',spec.criticHidden);
opts = agent.AgentOptions;
assert(opts.SampleTime == spec.sampleTime && opts.DiscountFactor == spec.discountFactor && ...
    opts.MiniBatchSize == spec.miniBatchSize && opts.ExperienceHorizon == spec.experienceHorizon && ...
    opts.NumEpoch == spec.numEpoch && opts.EntropyLossWeight == spec.entropyLossWeight, ...
    'Modular:OptionsMismatch','Checkpoint PPO options differ from the saved model specification.');
assert(opts.ActorOptimizerOptions.LearnRate == spec.actorLearnRate && ...
    opts.CriticOptimizerOptions.LearnRate == spec.criticLearnRate, ...
    'Modular:OptionsMismatch','Checkpoint optimizer rates differ from the saved model specification.');
end

function checkNamed(layers,prefix,widths)
% 按層名檢查分支各隱藏層寬度，避免 layerGraph 排序差異誤判。
for k=1:numel(widths)
    index=find(strcmp({layers.Name},sprintf('%s_fc%d',prefix,k)));
    assert(isscalar(index) && layers(index).OutputSize==widths(k), ...
        'Modular:ArchitectureMismatch','Checkpoint hidden-layer layout differs from the saved profile.');
end
end

function checkLayers(layers,units,widths)
% 檢查 LSTM 數量／單元及主幹全連接層尺寸，不修改網路。
actualUnits = []; actualWidths = [];
for k=1:numel(layers)
    if isa(layers(k),'nnet.cnn.layer.LSTMLayer'), actualUnits(end+1)=layers(k).NumHiddenUnits; end %#ok<AGROW>
    if isa(layers(k),'nnet.cnn.layer.FullyConnectedLayer'), actualWidths(end+1)=layers(k).OutputSize; end %#ok<AGROW>
end
if units == 0, expected=[]; else, expected=units; end
% Graph layer ordering can differ for the two actor branches.
assert(isequal(actualUnits,expected) && isequal(sort(actualWidths),sort(widths)), ...
    'Modular:ArchitectureMismatch','Checkpoint network differs from the saved model specification.');
end
