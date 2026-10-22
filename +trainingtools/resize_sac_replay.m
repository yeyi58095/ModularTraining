function agent=resize_sac_replay(agent,capacity)
% R2024b saved-state reconstruction avoids AgentOptions setter optimizer reset.
assert(strcmp(version('-release'),'2024b') && isa(agent,'rl.agent.rlSACAgent'));
validateattributes(capacity,{'numeric'},{'scalar','integer','positive','finite'});
before=saveobj(agent);
required={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','TargetCritic','ExperienceBuffer','PolicyState'};
assert(all(isfield(before,required)),'SAC:State','Checkpoint lacks required learning state.');
assert(capacity>=before.ExperienceBuffer.MaxLength,'SAC:Capacity','Only retaining or growing replay is supported.');
data=allExperiences(before.ExperienceBuffer);
s=before;
s.ExperienceBuffer=copy(before.ExperienceBuffer);
resize(s.ExperienceBuffer,capacity);
s.AgentOptions.ExperienceBufferLength=capacity;
agent=rl.agent.rlSACAgent.loadobj(s);
after=saveobj(agent);
for field={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(before.(field{1}),after.(field{1})),'SAC:State','Changed %s.',field{1});
end
for field={'Actor','Critic','TargetCritic'}
    x=before.(field{1});y=after.(field{1});
    for k=1:numel(x)
        assert(isequaln(getLearnableParameters(x(k)),getLearnableParameters(y(k))),'SAC:Weights','Changed %s weights.',field{1});
    end
end
assert(isequaln(data,allExperiences(after.ExperienceBuffer)),'SAC:Replay','Replay data changed.');
assert(after.ExperienceBuffer.MaxLength==capacity && agent.AgentOptions.ExperienceBufferLength==capacity);
end
