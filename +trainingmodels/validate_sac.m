function validate_sac(agent,spec)
assert(isa(agent,'rl.agent.rlSACAgent'),'Modular:AgentType','Expected a SAC checkpoint.');
critics=getCritic(agent);
assert(numel(critics)==2,'Modular:ArchitectureMismatch','Expected twin Q critics.');
nets={getModel(getActor(agent)),getModel(critics(1)),getModel(critics(2))};
for k=1:numel(nets)
    layers=nets{k}.Layers; units=[];
    for j=1:numel(layers)
        if isa(layers(j),'nnet.cnn.layer.LSTMLayer'),units(end+1)=layers(j).NumHiddenUnits;end %#ok<AGROW>
    end
    if spec.lstmUnits>0
        expected=spec.lstmUnits;
    else
        expected=[];
        fc=layers(arrayfun(@(x) isa(x,'nnet.cnn.layer.FullyConnectedLayer'),layers));
        widths=[fc.OutputSize];
        assert(isfield(spec,'hiddenUnits') && any(widths==spec.hiddenUnits) && ...
            all(widths==spec.hiddenUnits | widths==1), ...
            'Modular:ArchitectureMismatch','SAC feedforward widths mismatch.');
    end
    assert(isequal(units,expected),'Modular:ArchitectureMismatch','SAC recurrent size mismatch.');
end
opts=agent.AgentOptions;
fields={'SampleTime','DiscountFactor','MiniBatchSize','SequenceLength', ...
    'ExperienceBufferLength','NumWarmStartSteps','LearningFrequency', ...
    'MaxMiniBatchPerEpoch','TargetSmoothFactor'};
keys={'sampleTime','discountFactor','miniBatchSize','sequenceLength', ...
    'experienceBufferLength','numWarmStartSteps','learningFrequency', ...
    'maxMiniBatchPerEpoch','targetSmoothFactor'};
for k=1:numel(fields)
    assert(opts.(fields{k})==spec.(keys{k}),'Modular:OptionsMismatch','SAC option mismatch: %s',fields{k});
end
assert(opts.ActorOptimizerOptions.LearnRate==spec.actorLearnRate && ...
    all([opts.CriticOptimizerOptions.LearnRate]==spec.criticLearnRate) && ...
    opts.EntropyWeightOptions.LearnRate==spec.entropyLearnRate && ...
    opts.EntropyWeightOptions.TargetEntropy==spec.targetEntropy, ...
    'Modular:OptionsMismatch','SAC optimizer/entropy settings mismatch.');
assert(~opts.ResetExperienceBufferBeforeTraining && opts.InfoToSave.ExperienceBuffer && ...
    opts.InfoToSave.Optimizer && opts.InfoToSave.Target && opts.InfoToSave.PolicyState, ...
    'Modular:OptionsMismatch','SAC must preserve replay, optimizer and target data.');
end
