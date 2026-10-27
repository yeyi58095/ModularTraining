function agent=set_sac_critic_rate(agent,rate)
% R2024b value optimizer edit; preserve all states except critic rates.
assert(strcmp(version('-release'),'2024b') && isa(agent,'rl.agent.rlSACAgent'));
validateattributes(rate,{'numeric'},{'scalar','positive','finite'});
before=saveobj(agent);s=before;
for k=1:numel(s.CriticOptimizer)
    assert(~isa(s.CriticOptimizer(k),'handle'));
    s.AgentOptions.CriticOptimizerOptions(k).LearnRate=rate;
    s.CriticOptimizer(k).LearnRate=rate;
end
agent=rl.agent.rlSACAgent.loadobj(s);after=saveobj(agent);
for k=1:numel(after.CriticOptimizer)
    assert(after.CriticOptimizer(k).LearnRate==rate && agent.AgentOptions.CriticOptimizerOptions(k).LearnRate==rate);
    check=after.CriticOptimizer(k);check.LearnRate=before.CriticOptimizer(k).LearnRate;
    assert(isequaln(check,before.CriticOptimizer(k)),'Critic optimizer state changed.');
end
for field={'ActorOptimizer','EntropyOptimizer','PolicyState'}
    assert(isequaln(before.(field{1}),after.(field{1})),'Other optimizer/state changed.');
end
for field={'Actor','Critic','TargetCritic'}
    x=before.(field{1});y=after.(field{1});
    for k=1:numel(x),assert(isequaln(getLearnableParameters(x(k)),getLearnableParameters(y(k))));end
end
[x,ids]=getLastNData(before.ExperienceBuffer,before.ExperienceBuffer.Length);
[y,newIds]=getLastNData(after.ExperienceBuffer,after.ExperienceBuffer.Length);
assert(isequaln(x,y) && isequaln(ids,newIds),'Replay changed.');
end
