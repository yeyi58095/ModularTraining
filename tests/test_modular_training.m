function test_modular_training()
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
obs=rlNumericSpec([10 1]); obs.Name='observation';
act=rlNumericSpec([1 1],'LowerLimit',-1,'UpperLimit',1);
profiles=["ppo_lstm128","ppo_lstm256","ppo_mlp"];
for name=profiles
    spec=trainingmodels.load_profile(name);
    agent=trainingmodels.build_agent(spec,obs,act,'cpu');
    trainingmodels.validate_agent(agent,spec);
    action=getAction(agent,{zeros(10,1)});
    assert(isscalar(action{1}) && isfinite(action{1}));
    wrong=spec; wrong.lstmUnits=spec.lstmUnits+1;
    rejected=false;
    try, trainingmodels.validate_agent(agent,wrong); catch e, rejected=strcmp(e.identifier,'Modular:ArchitectureMismatch'); end
    assert(rejected,'Wrong architecture must be rejected.');
    fprintf('PASS build/validate/action: %s\n',name);
end
info=retry(model="ppo_lstm256",workers=2,device="cpu",start=false);
cfg=jsondecode(fileread(fullfile(info.sessionDir,'control.json')));
assert(cfg.numWorkers==2 && strcmp(cfg.scriptDir,fullfile(root,'runtime')));
assert(isfile(fullfile(info.sessionDir,'model_source','+trainingmodels','build_agent.m')));
resumed=retry(resume=info.sessionDir,start=false);
cfg2=jsondecode(fileread(fullfile(resumed.sessionDir,'control.json')));
assert(cfg2.numWorkers==2 && strcmp(resumed.model,'ppo_lstm256'));
rejected=false;
try, retry(resume=info.sessionDir,model="ppo_mlp",start=false); catch e, rejected=strcmp(e.identifier,'Modular:ModelMismatch'); end
assert(rejected,'Wrong resume model must be rejected.');
old=path; guard=onCleanup(@()path(old)); %#ok<NASGU>
override=training(cfg,struct());
agent=override.agentFactory(obs,act,'cpu'); override.agentValidator(agent);
addpath(fullfile(root,'runtime'));
mdl=fullfile(root,'runtime','FAFA_Simulation.slx');
load_system(mdl);
assert(strcmp(get_param('FAFA_Simulation','FileName'),mdl),'Wrong environment model loaded.');
close_system('FAFA_Simulation',0);
fprintf('PASS: launcher prepare/resume, saved profiles, mismatch rejection, snapshot factory, isolated SLX load.\n');
end
