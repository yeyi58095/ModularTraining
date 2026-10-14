function [signals,definition]=instrument_reward(mdl)
% Log actual reward-sum inputs in an evaluation copy; never change scoring.
names={'cross_track','distance_rate','heading','curvature_distance', ...
    'roll_rate','yaw_rate','yaw_tracking','distance_bonus','action_limit','action_change'};
expected={'Gain9','Gain13','Gain17','Gain20','Gain23','Gain18', ...
    'Gain19','Gain11','MATLAB Function20','MATLAB Function16'};
sumBlock=[mdl '/OBSERVATION/Sum3'];ports=get_param(sumBlock,'PortHandles');
assert(numel(ports.Inport)==10 && strcmp(get_param(sumBlock,'Inputs'),'++++++++++'), ...
    'RewardAudit:Graph','Unexpected reward sum.');
signals=struct('name',{},'block',{},'port',{});
definition=struct('terms',struct([]),'parameters',struct([]));
for i=1:10
    line=get_param(ports.Inport(i),'Line');src=get_param(line,'SrcPortHandle');
    block=get_param(src,'Parent');port=get_param(src,'PortNumber');
    assert(strcmp(block,[mdl '/OBSERVATION/' expected{i}]),'RewardAudit:Graph','Reward source changed.');
    name=['reward_' names{i}];enable(src,name);
    signals(end+1)=struct('name',name,'block',block,'port',port); %#ok<AGROW>
    definition.terms(i).name=name;definition.terms(i).sum_port=i;
    definition.terms(i).block=block;
end
extra={'reward_total','Sum3';'reward_normalized_d','MATLAB Function1'; ...
    'reward_normalized_curvature','MATLAB Function11'; ...
    'reward_bonus_indicator','MATLAB Function22'};
for i=1:size(extra,1)
    block=[mdl '/OBSERVATION/' extra{i,2}];h=get_param(block,'PortHandles');enable(h.Outport(1),extra{i,1});
    signals(end+1)=struct('name',extra{i,1},'block',block,'port',1); %#ok<AGROW>
end
spec={'Gain12','Gain';'Constant19','Value';'Gain11','Gain';'Constant10','Value';'Constant14','Value'};
for i=1:size(spec,1)
    definition.parameters(i).block=spec{i,1};definition.parameters(i).parameter=spec{i,2};
    definition.parameters(i).value=get_param([mdl '/OBSERVATION/' spec{i,1}],spec{i,2});
end
end
function enable(port,name)
set_param(port,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name, ...
    'DataLoggingDecimateData','off','DataLoggingLimitDataPoints','off');
end
