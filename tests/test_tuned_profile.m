function test_tuned_profile()
% Verify the selected changes reach the actual agent and its saved snapshot.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
name='ppo_lstm128_tuned_stability_20260923_v1';
baseline=trainingmodels.load_profile('ppo_lstm128');
spec=trainingmodels.load_profile(name);
assert(spec.actorLearnRate==2.5e-5 && spec.numEpoch==2);
fields=fieldnames(baseline);
for k=1:numel(fields)
    field=fields{k};
    if ismember(field,{'name','actorLearnRate','numEpoch'}), continue; end
    assert(isequal(spec.(field),baseline.(field)),'Unexpected change to %s',field);
end
obs=rlNumericSpec([10 1]); obs.Name='observation';
act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
agent=trainingmodels.build_agent(spec,obs,act,'cpu');
trainingmodels.validate_agent(agent,spec);
action=getAction(agent,{zeros(10,1)});
assert(isscalar(action{1}) && isfinite(action{1}));
rejected=false;
try, trainingmodels.validate_agent(agent,baseline); catch e, rejected=strcmp(e.identifier,'Modular:OptionsMismatch'); end
assert(rejected,'Baseline options must not silently accept tuned agent.');
info=retry(model=name,device="cpu",start=false);
assert(strcmp(fileparts(info.sessionDir),fullfile(root,'+trainingmodels',name,'runs')));
saved=jsondecode(fileread(fullfile(info.sessionDir,'model.json')));
assert(saved.actorLearnRate==spec.actorLearnRate && saved.numEpoch==spec.numEpoch);
cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
old=path; guard=onCleanup(@()path(old)); %#ok<NASGU>
overrides=training(cfg,struct());
savedAgent=overrides.agentFactory(obs,act,'cpu'); overrides.agentValidator(savedAgent);
assert(savedAgent.AgentOptions.NumEpoch==2);
assert(savedAgent.AgentOptions.ActorOptimizerOptions.LearnRate==2.5e-5);
fprintf('PASS: tuned options, unchanged baseline fields, valid action, mismatch rejection, saved snapshot factory.\n');
end
