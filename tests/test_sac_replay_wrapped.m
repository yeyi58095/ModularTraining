function test_sac_replay_wrapped()
% Synthetic replay records, no training. Exercise full/wrapped ring storage.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
obs=rlNumericSpec([10 1]);act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
spec=trainingmodels.load_profile('sac_lstm128');spec.lstmUnits=16;spec.numWarmStartSteps=64;
cases=[128 32;128 128;128 173;128 400;100000 100037];
for row=1:size(cases,1)
    capacity=cases(row,1);count=cases(row,2);
    spec.experienceBufferLength=capacity;
    agent=trainingmodels.build_agent(spec,obs,act,'cpu');
    e=repmat(struct('Observation',{{zeros(10,1)}},'Action',{{0}}, ...
        'Reward',0,'NextObservation',{{zeros(10,1)}},'IsDone',0),count,1);
    for k=1:count
        e(k).Observation={ones(10,1)*k};e(k).NextObservation={ones(10,1)*(k+1)};
        e(k).Reward=k;e(k).IsDone=double(mod(k,17)==0);
    end
    append(agent.ExperienceBuffer,e);
    raw=allExperiences(agent.ExperienceBuffer);
    [chronological,ids]=getLastNData(agent.ExperienceBuffer,agent.ExperienceBuffer.Length);
    assert(isequal([chronological.Reward],max(1,count-capacity+1):count));
    grown=trainingtools.resize_sac_replay(agent,capacity*5);
    [actual,actualIDs]=getLastNData(grown.ExperienceBuffer,grown.ExperienceBuffer.Length);
    assert(isequaln(chronological,actual) && isequaln(ids,actualIDs));
    assert(isequaln(raw,allExperiences(agent.ExperienceBuffer)) && agent.ExperienceBuffer.MaxLength==capacity);
    if count==173,assert(~isequaln(raw,allExperiences(grown.ExperienceBuffer)));end
    if capacity==100000
        file=fullfile(root,'tests','output','sac-replay-full-ring.mat');
        save(file,'grown','-v7.3');loaded=load(file,'grown');
        [reloaded,reloadedIDs]=getLastNData(loaded.grown.ExperienceBuffer,loaded.grown.ExperienceBuffer.Length);
        assert(isequaln(chronological,reloaded) && isequaln(ids,reloadedIDs));
        assert(loaded.grown.ExperienceBuffer.MaxLength==500000);
        clear loaded reloaded reloadedIDs
    end
    fprintf('PASS: count=%d, chronology, terminal markers, tracker IDs and parent isolation.\n',count);
end
end
