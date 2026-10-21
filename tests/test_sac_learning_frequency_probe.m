function test_sac_learning_frequency_probe()
% Bounded probe of serial training and legacy/direct replay entry.
% Does not establish which trainer a parallel train() call selects.
% No pool, flight environment, existing checkpoint, or production run changes.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
out=fullfile(root,'tests','output','sac-frequency-probe');
if ~isfolder(out),mkdir(out);end
assert(isempty(gcp('nocreate')),'Probe:Pool','Run in a fresh MATLAB process.');
cleanup=onCleanup(@() profile('off')); %#ok<NASGU>
obs=rlNumericSpec([10 1]); act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
spec=trainingmodels.load_profile('sac_lstm128');
spec.lstmUnits=16;spec.miniBatchSize=4;spec.sequenceLength=4;
spec.numWarmStartSteps=8;spec.experienceBufferLength=128;
results=struct([]);
deviceAudits=struct([]);
devices={'cpu'};
if gpuDeviceCount('available')>0,devices{end+1}='gpu';end
for d=1:numel(devices)
 for frequency=[1 8]
  rng(20261021);spec.learningFrequency=frequency;
  agent=trainingmodels.build_agent(spec,obs,act,devices{d});
  a=getActor(agent);c=getCritic(agent);
  assert(string(a.UseDevice)==string(devices{d}) && ...
   string(c(1).UseDevice)==string(devices{d}) && string(c(2).UseDevice)==string(devices{d}));
  env=rlFunctionEnv(obs,act,@step,@reset);
  options=rlTrainingOptions('MaxEpisodes',1,'MaxStepsPerEpisode',32,...
   'UseParallel',false,'Plots','none','Verbose',false,...
   'StopTrainingCriteria','EpisodeCount','StopTrainingValue',1);
  profile clear;profile on;t=tic;
  history=train(agent,env,options);
  elapsed=toc(t);profile off;p=profile('info');
  row=summary(p,'serial',devices{d},frequency,elapsed);
  row.episodeSteps=double(history.EpisodeSteps(end));
  results=[results;row]; %#ok<AGROW>
  fprintf('%s\n',jsonencode(row));
  before=getLearnableParameters(getActor(agent));
  profile clear;profile on;t=tic;
  % Legacy ExpSyncParallelTrainer entry, NOT the newer default OffPolicyTrainer.
  % Replay already contains this synthetic episode; excludes worker/transfer work.
  for k=1:32,learnFromExperiencesInMemory(agent);end
  elapsed=toc(t);profile off;p=profile('info');
  row=summary(p,'direct_replay',devices{d},frequency,elapsed);
  row.episodeSteps=0;results=[results;row]; %#ok<AGROW>
  assert(~isequaln(before,getLearnableParameters(getActor(agent))),'Probe:NoUpdate','Direct entry did not update actor.');
  fprintf('%s\n',jsonencode(row));
  % Small save/load device audit, never touches a production checkpoint.
  file=fullfile(out,sprintf('device-%s-f%d.mat',devices{d},frequency));
  save(file,'agent','-v7.3');s=load(file,'agent');
  a=getActor(s.agent);c=getCritic(s.agent);
  fprintf('RESTORED device=%s actor=%s critics=%s,%s\n',devices{d},a.UseDevice,c(1).UseDevice,c(2).UseDevice);
  audit=struct('requestedDevice',devices{d},'frequency',frequency,...
   'restoredActorDevice',char(string(a.UseDevice)),...
   'restoredCriticDevices',{{char(string(c(1).UseDevice)),char(string(c(2).UseDevice))}},...
   'actorWeightsPreserved',sameWeights(getActor(agent),a),...
   'replayLengthPreserved',s.agent.ExperienceBuffer.Length==agent.ExperienceBuffer.Length);
  originalCritics=getCritic(agent);
  audit.criticWeightsPreserved=sameWeights(originalCritics(1),c(1)) && sameWeights(originalCritics(2),c(2));
  assert(audit.actorWeightsPreserved && audit.criticWeightsPreserved && audit.replayLengthPreserved);
  original=saveobj(s.agent);
  restored=checkpoint_restore_sac_device(s.agent,devices{d});
  recovered=saveobj(restored);
  for field={'ActorOptimizer','CriticOptimizer','EntropyOptimizer','PolicyState'}
   assert(isequaln(original.(field{1}),recovered.(field{1})), ...
    'Probe:State','Device restoration changed %s',field{1});
  end
  assert(restored.ExperienceBuffer.Length==s.agent.ExperienceBuffer.Length);
  for k=1:numel(original.TargetCritic)
   assert(sameWeights(original.TargetCritic(k),recovered.TargetCritic(k)));
  end
  assert(sameWeights(getActor(s.agent),getActor(restored)));
  % Verify restored optimizers can actually perform subsequent learning.
  learnFromExperiencesInMemory(restored);
  audit.deviceRestorationAndLearningPassed=true;
  deviceAudits=[deviceAudits;audit]; %#ok<AGROW>
  clear agent s env history;
 end
end
for d=1:numel(devices)
 rows=results(strcmp({results.device},devices{d}));
 serial=rows(strcmp({rows.mode},'serial'));direct=rows(strcmp({rows.mode},'direct_replay'));
 assert(serial(1).batchCalls>serial(2).batchCalls,'Probe:Frequency','Serial frequency did not reduce calls.');
 assert(all([direct.batchCalls]==32),'Probe:DirectCount','Direct entry call count unexpected.');
end
report=struct('release',version('-release'),'scope','synthetic one process; no parallel performance or flight claim',...
 'spec',spec,'results',results,'deviceAudits',deviceAudits);
trainingcurriculum.write_json(fullfile(out,'report.json'),report);
fprintf('PASS: serial frequency gate, direct replay bypass, small save/load device audit.\n');
end
function yes=sameWeights(a,b)
x=getLearnableParameters(a);y=getLearnableParameters(b);
x=cellfun(@gather,x,'UniformOutput',false);y=cellfun(@gather,y,'UniformOutput',false);
yes=isequaln(x,y);
end
function row=summary(p,mode,device,frequency,elapsed)
table=p.FunctionTable;
names=string({table.FunctionName});
selected=endsWith(names,'rlSACAgent.learnFromBatchData_') | endsWith(names,'rlSACAgent>rlSACAgent.learnFromBatchData_');
if ~any(selected)
 selected=contains(names,'rlSACAgent') & contains(names,'learnFromBatchData_');
end
row=struct('mode',mode,'device',device,'frequency',frequency,'seconds',elapsed,...
 'batchCalls',sum([table(selected).NumCalls]),'episodeSteps',0);
end
function [o,r,done,info]=step(a,info)
info.n=info.n+1;info.x=.95*info.x+.05*a(1);
o=[info.x;zeros(9,1)];r=1-info.x^2-.01*a(1)^2;done=info.n>=32;
end
function [o,info]=reset()
info=struct('n',0,'x',.5);o=[info.x;zeros(9,1)];
end
