function out=reward_breakdown(experience,diagnostics,rewardVersion)
% Audit recorded components against every RL reward transition. No rescore.
if nargin<3,rewardVersion='legacy_spatial';end
assert(any(strcmp(rewardVersion,{'legacy_spatial','spatial_reward_v2'})), ...
    'RewardAudit:Version','Unknown reward definition.');
names={'cross_track','distance_rate','heading','curvature_distance', ...
    'roll_rate','yaw_rate','yaw_tracking','distance_bonus','action_limit','action_change'};
r=double(experience.Reward.Data(:));t=double(experience.Reward.Time(:));
total=diagnostics.getElement('reward_total').Values;
values=double(total.Data(:));times=double(total.Time(:));
% rl sim labels transition reward at t, whereas the signal is at t+DT.
assert(numel(values)==numel(r)+1 && numel(times)>1,'RewardAudit:Alignment','Unexpected logging lengths.');
dt=times(2)-times(1);idx=(2:numel(values))';
assert(dt>0 && max(abs(times(idx)-t-dt))<1e-7 && ...
    max(abs(values(idx)-r))<1e-8,'RewardAudit:Alignment','Transition rewards do not match logged next-step values.');
out=struct('steps',numel(r),'episode_reward',sum(r),'signal_time_offset_seconds',dt);
out.reward_version=char(rewardVersion);
parts=zeros(numel(r),10);
for i=1:10
    parts(:,i)=sample(['reward_' names{i}]);
    out.terms(i)=struct('name',names{i},'sum',sum(parts(:,i)), ...
        'mean',mean(parts(:,i)),'min',min(parts(:,i)),'max',max(parts(:,i)));
end
out.component_sum=sum(parts,'all');
out.max_per_step_residual=max(abs(sum(parts,2)-r));
assert(out.max_per_step_residual<1e-8,'RewardAudit:Sum','Reward sum does not match components.');
d=sample('guidance_d');dn=sample('reward_normalized_d');dis=sample('distance_to_window_target');
indicator=sample('reward_bonus_indicator');
isV2=strcmp(rewardVersion,'spatial_reward_v2');
if isV2
    a=zeros(size(d));b=0.5*max(0,1-abs(d)/10);
else
    a=0.5*double(dis>=30 & dis<=150);b=0.5*double(dn<=10);
end
assert(max(abs(dn-d/30))<1e-8 && max(abs(indicator-a-b))<1e-8 && ...
    max(abs(parts(:,8)-0.1*(1+a+b)))<1e-8,'RewardAudit:Bonus','Bonus wiring/formula changed.');
if isV2
    out.bonus=struct('base_sum',0.1*numel(r),'distance_band_sum',0, ...
        'physical_close_distance_sum',sum(0.1*b),'physical_close_bonus_fraction',mean(b>0), ...
        'physical_d_at_most_10m_fraction',mean(d<=10));
else
out.bonus=struct('base_sum',0.1*numel(r),'distance_band_sum',sum(0.1*a), ...
    'normalized_d_gate_sum',sum(0.1*b),'distance_band_fraction',mean(a>0), ...
    'normalized_d_gate_fraction',mean(b>0),'physical_d_at_most_10m_fraction',mean(d<=10), ...
    'route_nearest_distance_mean_m',mean(dis));
end
out.action_change_penalty_fraction=mean(parts(:,10)<0);
kt=sample('reward_normalized_curvature');
factor=ones(size(kt));if ~isV2,factor(abs(kt)>=1/55)=0.5;end
assert(max(abs(parts(:,1)-0.2*(1-abs(dn.*factor))))<1e-8, ...
    'RewardAudit:Curvature','Cross-track curvature gate changed.');
if isV2
    out.curvature_gate=struct('applied_fraction',0, ...
        'note','Direct cross-track penalty has no curvature relief; separate curvature_distance term is retained.');
else
out.curvature_gate=struct('applied_fraction',mean(abs(kt)>=1/55), ...
    'fraction_if_threshold_were_physical_1_over_55',mean(abs(kt)>=1), ...
    'note','Input is curvature/(1/55). Current gate compares this normalized value to 1/55, equivalent to raw curvature 1/3025. Intent unconfirmed.');
end
out.scope='Frozen-policy simulation only; neither training attribution nor qualification.';
    function v=sample(name)
        q=diagnostics.getElement(name).Values;qt=double(q.Time(:));v=double(q.Data(:));
        assert(numel(v)==numel(times) && max(abs(qt-times))<1e-7, ...
            'RewardAudit:Alignment','Signal %s time grid differs.',name);
        v=v(idx);assert(all(isfinite(v)),'RewardAudit:Nonfinite','Nonfinite signal.');
    end
end
