function agent=build_sac(spec,obs,act,device)
% MATLAB's SAC builder supplies an unbounded Gaussian mean and twin Q critics.
% SAC performs its own squashing; do not reuse PPO's tanh mean network.
assert(isequal(obs.Dimension,[10 1]) && isequal(act.Dimension,[1 1]) && ...
    isequal(act.LowerLimit,-1) && isequal(act.UpperLimit,1), ...
    'Modular:Environment','SAC candidate requires the FAFA observation/action contract.');
opts=rlSACAgentOptions('SampleTime',spec.sampleTime, ...
    'DiscountFactor',spec.discountFactor,'MiniBatchSize',spec.miniBatchSize, ...
    'SequenceLength',spec.sequenceLength,'ExperienceBufferLength',spec.experienceBufferLength, ...
    'NumWarmStartSteps',spec.numWarmStartSteps,'LearningFrequency',spec.learningFrequency, ...
    'MaxMiniBatchPerEpoch',spec.maxMiniBatchPerEpoch,'NumEpoch',1, ...
    'TargetSmoothFactor',spec.targetSmoothFactor);
opts.ActorOptimizerOptions.LearnRate=spec.actorLearnRate;
opts.ActorOptimizerOptions.GradientThreshold=1;
for k=1:2
    opts.CriticOptimizerOptions(k).LearnRate=spec.criticLearnRate;
    opts.CriticOptimizerOptions(k).GradientThreshold=1;
end
opts.EntropyWeightOptions.LearnRate=spec.entropyLearnRate;
opts.EntropyWeightOptions.TargetEntropy=spec.targetEntropy;
opts.EntropyWeightOptions.EntropyWeight=spec.initialEntropyWeight;
% Keep replay across process checkpoints and subsequent train calls.
opts.ResetExperienceBufferBeforeTraining=false;
opts.InfoToSave.ExperienceBuffer=true;
opts.InfoToSave.Optimizer=true;
opts.InfoToSave.Target=true;
opts.InfoToSave.PolicyState=true; % Preserve learned SAC entropy weight on resume.
useRNN=spec.lstmUnits>0;units=spec.lstmUnits;
if ~useRNN
    assert(isfield(spec,'hiddenUnits') && spec.sequenceLength==1,'Modular:Architecture','Feedforward SAC requires hiddenUnits and sequenceLength1.');
    units=spec.hiddenUnits;
end
agent=rlSACAgent(obs,act,rlAgentInitializationOptions( ...
    'NumHiddenUnit',units,'UseRNN',useRNN),opts);
actor=getActor(agent); actor.UseDevice=device; agent=setActor(agent,actor);
critics=getCritic(agent);
for k=1:numel(critics), critics(k).UseDevice=device; end
agent=setCritic(agent,critics);
end
