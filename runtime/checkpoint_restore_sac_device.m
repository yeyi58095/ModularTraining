function agent=checkpoint_restore_sac_device(agent,device)
% Restore SAC device via saved-state reconstruction; setters alone reset state.
assert(strcmp(version('-release'),'2024b'),'Checkpoint:Release','Device restoration validated only on R2024b.');
assert(isa(agent,'rl.agent.rlSACAgent') && any(strcmp(device,{'cpu','gpu'})));
a=getActor(agent);c=getCritic(agent);
if string(a.UseDevice)==string(device) && all(arrayfun(@(x) string(x.UseDevice)==string(device),c))
    return;
end
s=saveobj(agent);
required={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','TargetCritic','ExperienceBuffer','PolicyState'};
assert(all(isfield(s,required)),'Checkpoint:State','SAC checkpoint must preserve optimizer, targets, replay and policy state.');
s.Actor.UseDevice=device;
for k=1:numel(s.Critic),s.Critic(k).UseDevice=device;end
for k=1:numel(s.TargetCritic),s.TargetCritic(k).UseDevice=device;end
agent=rl.agent.rlSACAgent.loadobj(s);
a=getActor(agent);c=getCritic(agent);
assert(string(a.UseDevice)==string(device) && all(arrayfun(@(x) string(x.UseDevice)==string(device),c)), ...
    'Checkpoint:Device','Restored SAC device mismatch.');
fprintf('Restored SAC device=%s with serialized optimizer, target, replay and policy state.\n',device);
end
