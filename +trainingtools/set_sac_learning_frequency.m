function [agent,verifyAfterReload]=set_sac_learning_frequency(agent,frequency)
% Change the update interval on a saved R2024b SAC agent without resetting its optimizers.
assert(strcmp(version('-release'),'2024b') && isa(agent,'rl.agent.rlSACAgent'), ...
    'SAC:LearningFrequency','Requires an R2024b SAC agent.');
validateattributes(frequency,{'numeric'},{'scalar','integer','positive','finite'});
before=saveobj(agent);
required={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState','TargetCritic','ExperienceBuffer'};
assert(all(isfield(before,required)), 'SAC:State','Checkpoint lacks required learning state.');
assert(before.AgentOptions.LearningFrequency==1 && frequency==2, ...
    'SAC:LearningFrequency','Expected an update interval change from 1 to 2.');
state=before;
assert(~isa(state.AgentOptions,'handle'),'SAC:LearningFrequency','Requires value agent options.');
state.AgentOptions.LearningFrequency=frequency;
agent=rl.agent.rlSACAgent.loadobj(state);
verifyAfterReload=@(reloaded) verifyState(state,reloaded);
verifyAfterReload(agent);
end

function verifyState(expected,agent)
actual=saveobj(agent);
assert(isequaln(expected.AgentOptions,actual.AgentOptions), ...
    'SAC:Options','SAC options differ after changing the update interval.');
for field={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    key=field{1};
    assert(isequaln(expected.(key),actual.(key)),'SAC:State','Changed %s.',key);
end
for field={'Actor','Critic','TargetCritic'}
    key=field{1};
    before=expected.(key); after=actual.(key);
    assert(numel(before)==numel(after),'SAC:Weights','Changed number of %s networks.',key);
    for k=1:numel(before)
        assert(isequaln(getLearnableParameters(before(k)),getLearnableParameters(after(k))), ...
            'SAC:Weights','Changed %s weights.',key);
    end
end
before=expected.ExperienceBuffer; after=actual.ExperienceBuffer;
assert(strcmp(class(before),class(after)) && before.Length==after.Length && before.MaxLength==after.MaxLength, ...
    'SAC:Replay','Changed replay type, length or capacity.');
[data,ids]=getLastNData(before,before.Length);
[restoredData,restoredIds]=getLastNData(after,after.Length);
assert(isequaln(data,restoredData) && isequaln(ids,restoredIds), ...
    'SAC:Replay','Changed chronological replay or data-source IDs.');
end
