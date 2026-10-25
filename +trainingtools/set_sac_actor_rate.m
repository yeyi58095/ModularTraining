function agent=set_sac_actor_rate(agent,rate)
% R2024b value-optimizer edit retains Adam moments/counters and replay.
assert(strcmp(version('-release'),'2024b') && isa(agent,'rl.agent.rlSACAgent'));
validateattributes(rate,{'numeric'},{'scalar','positive','finite'});
before=saveobj(agent);
assert(all(isfield(before,{'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState','TargetCritic','ExperienceBuffer'})));
s=before;oldRate=s.ActorOptimizer.LearnRate;
assert(~isa(s.ActorOptimizer,'handle'),'SAC:Optimizer','Requires value optimizer.');
s.AgentOptions.ActorOptimizerOptions.LearnRate=rate;
s.ActorOptimizer.LearnRate=rate;
agent=rl.agent.rlSACAgent.loadobj(s);after=saveobj(agent);
assert(agent.AgentOptions.ActorOptimizerOptions.LearnRate==rate && after.ActorOptimizer.LearnRate==rate);
check=after.ActorOptimizer;check.LearnRate=oldRate;
assert(isequaln(check,before.ActorOptimizer),'SAC:State','Actor moments or counters changed.');
for field={'CriticOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(before.(field{1}),after.(field{1})),'SAC:State','Changed %s.',field{1});
end
for field={'Actor','Critic','TargetCritic'}
    x=before.(field{1});y=after.(field{1});
    for k=1:numel(x)
        assert(isequaln(getLearnableParameters(x(k)),getLearnableParameters(y(k))));
    end
end
[x,ids]=getLastNData(before.ExperienceBuffer,before.ExperienceBuffer.Length);
[y,newIds]=getLastNData(after.ExperienceBuffer,after.ExperienceBuffer.Length);
assert(isequaln(x,y) && isequaln(ids,newIds),'SAC:Replay','Replay changed.');
end
