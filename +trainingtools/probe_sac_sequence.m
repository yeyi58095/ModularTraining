function result=probe_sac_sequence(agent,experience)
% CPU inference on one episode prefix, zero state then sequential updates.
% Gaussian parameters are pre-action-transform; Q uses recorded actions.
actor=getActor(agent);critics=getCritic(agent);
actor.UseDevice='cpu';actor=zeroState(actor);
for k=1:numel(critics),critics(k).UseDevice='cpu';critics(k)=zeroState(critics(k));end
beforeActor=getLearnableParameters(actor);
beforeCritic=arrayfun(@(c) getLearnableParameters(c),critics,'UniformOutput',false);
n=numel(experience);mu=zeros(n,1);sigma=mu;q=zeros(n,numel(critics));
for t=1:n
    e=experience(t);
    [p,state]=evaluate(actor,e.Observation);
    mu(t)=number(p{1});sigma(t)=number(p{2});actor=assignState(actor,state);
    for k=1:numel(critics)
        [v,state]=getValue(critics(k),e.Observation,e.Action);
        q(t,k)=number(v);critics(k)=assignState(critics(k),state);
    end
end
assert(isequaln(beforeActor,getLearnableParameters(actor)));
for k=1:numel(critics),assert(isequaln(beforeCritic{k},getLearnableParameters(critics(k))));end
assert(all(isfinite([mu;sigma;q(:)])) && all(sigma>0),'SAC:Probe','Nonfinite output or invalid std.');
result=struct('steps',n,'burn_in_steps',min(64,n),'mean',mu, ...
    'std',sigma,'q_recorded_action',q,'weights_unchanged',true, ...
    'scope','Pre-transform Gaussian mean/std and twin Q on recorded actions. Not TD error, return calibration or a flight test.');
if n>64
    result.after_burn_in=struct('mean_abs',mean(abs(mu(65:end))), ...
        'std_mean',mean(sigma(65:end)),'q_mean',mean(q(65:end,:),1), ...
        'q_disagreement_mean',mean(abs(q(65:end,1)-q(65:end,2))));
end
end
function net=zeroState(net)
s=net.State;for k=1:numel(s),s{k}=0*s{k};end;net.State=s;
end
function net=assignState(net,s)
net.State=cellfun(@dlarray,s,'UniformOutput',false);
end
function x=number(x)
if isa(x,'dlarray'),x=extractdata(x);end
x=double(gather(x));assert(isscalar(x),'SAC:Probe','Only scalar action/Q supported.');
end
