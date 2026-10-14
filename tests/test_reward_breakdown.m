function test_reward_breakdown()
% Synthetic transition alignment, component conservation and unit diagnostics.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
t=(0:3)'*.1;d=[0;5;15;40];dn=d/30;dis=[50;5;15;40];kt=[0;.01;.5;1.2];
indicator=.5*double(dis>=30 & dis<=150)+.5*double(dn<=10);
names={'cross_track','distance_rate','heading','curvature_distance', ...
    'roll_rate','yaw_rate','yaw_tracking','distance_bonus','action_limit','action_change'};
values=zeros(4,10);factor=ones(4,1);factor(abs(kt)>=1/55)=.5;
values(:,1)=.2*(1-abs(dn.*factor));values(:,8)=.1*(1+indicator);
dataset=Simulink.SimulationData.Dataset;
for i=1:10,dataset=addSignal(dataset,values(:,i),t,['reward_' names{i}]);end
total=sum(values,2);
extra={'reward_total',total;'guidance_d',d;'reward_normalized_d',dn; ...
    'distance_to_window_target',dis;'reward_bonus_indicator',indicator; ...
    'reward_normalized_curvature',kt};
for i=1:size(extra,1),dataset=addSignal(dataset,extra{i,2},t,extra{i,1});end
experience=struct('Reward',timeseries(total(2:end),t(1:end-1)));
a=checkpointreview.reward_breakdown(experience,dataset);
assert(a.max_per_step_residual==0 && abs(a.component_sum-sum(total(2:end)))<1e-12);
assert(a.bonus.normalized_d_gate_fraction==1 && a.bonus.physical_d_at_most_10m_fraction==1/3);
assert(a.curvature_gate.applied_fraction==2/3);
assert(a.curvature_gate.fraction_if_threshold_were_physical_1_over_55==1/3);
experience.Reward.Data(1)=experience.Reward.Data(1)+.001;
try
 checkpointreview.reward_breakdown(experience,dataset);error('Test:ExpectedFailure','Expected alignment refusal.');
catch err
 assert(strcmp(err.identifier,'RewardAudit:Alignment'));
end
function ds=addSignal(ds,values,t,name)
s=Simulink.SimulationData.Signal;s.Name=name;s.Values=timeseries(values,t);
ds=ds.addElement(s);
end
fprintf('PASS reward conservation, transition alignment refusal and normalized-unit diagnostics.\n');
end
