function test_sac_actor_pilot_preparation(mode)
% Real archived Agent1600; prepare only, never launch train or sim.
if nargin==0,mode="actor";end
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
f=jsondecode(fileread(fullfile(root,'tests','output','sac-paper-probe-fixture.json')));
source=string(f.folder);archive=fullfile(root,'artifacts','incoming','sac-actor-half-1500-package-20261107','20261107_002801_recovery_tpbb65eb4c');
for name=["environment","model_source"]
    if ~isfolder(fullfile(source,name)),copyfile(fullfile(archive,name),fullfile(source,name));end
end
for name=["environment.json","curriculum.json","checkpoint_storage.json"]
    copyfile(fullfile(archive,name),fullfile(source,name));
end
original=fullfile(root,'artifacts','incoming','sac-review-cycle-2100-20261116','child');
copyfile(fullfile(original,'curriculum_state.json'),fullfile(source,'curriculum_state.json'));
cfg=jsondecode(fileread(fullfile(original,'control.json')));cfg.curriculumName='sac_actor_pilot_preparation_fixture';
trainingcurriculum.write_json(fullfile(source,'control.json'),cfg);
file=fullfile(source,'checkpoints','Agent1600.mat');hash=checkpointreview.sha256(file);
v=whos('-file',file);name='saved_agent';if ~any(strcmp({v.name},name)),name='Agent_Stage2';end
d=load(file,name);before=saveobj(d.(name));clear d;
scales=[1 .5];capacities=[50000 50000];
if mode=="replay_retention",scales=[1 1];capacities=[50000 500000];end
for trial=1:2
    scale=scales(trial);capacity=capacities(trial);
    r=struct('schema_version',1,'checkpoint_episode',1600,'expected_checkpoint_sha256',hash, ...
        'actor_learning_rate_scale',scale,'expected_actor_learning_rate',1.5e-4, ...
        'experience_buffer_length',capacity,'episodes_per_process',100,'max_additional_episodes',100, ...
        'guard',struct('schema_version',1,'window',100,'patience',3,'reward_ratio',.5,'steps_ratio',.5, ...
        'min_reference_reward',500,'min_reference_steps',500));
    recipe=string(tempname(fullfile(root,'tests','output')))+".json";trainingcurriculum.write_json(recipe,r);
    info=trainingtools.prepare_recovery_training(source,recipe);
    child=fullfile(info.sessionDir,'checkpoints','Agent1600.mat');vars=whos('-file',child);n='saved_agent';
    if ~any(strcmp({vars.name},n)),n='Agent_Stage2';end
    loaded=load(child,n);after=saveobj(loaded.(n));clear loaded;
    actorOptimizer=after.ActorOptimizer;actorOptimizer.LearnRate=before.ActorOptimizer.LearnRate;
    assert(isequaln(actorOptimizer,before.ActorOptimizer));
    for key={'CriticOptimizer','EntropyOptimizer','PolicyState'},assert(isequaln(before.(key{1}),after.(key{1})));end
    assert(after.ActorOptimizer.LearnRate==1.5e-4*scale);
    for key={'Actor','Critic','TargetCritic'}
        a=before.(key{1});b=after.(key{1});for k=1:numel(a),assert(isequaln(getLearnableParameters(a(k)),getLearnableParameters(b(k))));end
    end
    [x,xi]=getLastNData(before.ExperienceBuffer,50000);[y,yi]=getLastNData(after.ExperienceBuffer,50000);
    assert(isequaln(x,y) && isequaln(xi,yi));
    assert(after.ExperienceBuffer.MaxLength==capacity && after.ExperienceBuffer.Length==50000);
    g=jsondecode(fileread(fullfile(info.sessionDir,'training_guard.json')));
    assert(g.origin_episode==1600 && g.max_additional_episodes==100 && isfile(fullfile(info.sessionDir,'STOP')));
    assert(strcmp(hash,checkpointreview.sha256(file)) && isempty(dir(fullfile(info.sessionDir,'attempt_*'))));
end
fprintf('PILOT_PREP_OK (%s): real source weights, replay chronology, optimizer moments and alpha retained after prepare/save/reload; no training.\n',mode);
end
