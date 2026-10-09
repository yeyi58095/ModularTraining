function test_model_layout()
% Filesystem/launcher regression checks; no training or worker pool required.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
profiles=["ppo_lstm128","ppo_lstm256","ppo_mlp"];
for name=profiles
    spec=trainingmodels.load_profile(name);
    assert(strcmp(spec.name,name));
    info=retry(model=name,device="cpu",start=false);
    assert(strcmp(fileparts(info.sessionDir),fullfile(root,'+trainingmodels',name,'runs')));
    assert(strcmp(info.diagnosticDir,fullfile(info.sessionDir,'diagnostics')));
    saved=fullfile(info.sessionDir,'model_source','+trainingmodels');
    assert(isfile(fullfile(saved,name,name+'.m')));
    assert(isempty(dir(fullfile(saved,'**','runs'))),'Snapshots must exclude training outputs.');
    resumed=retry(resume=info.sessionDir,start=false);
    assert(strcmp(resumed.sessionDir,info.sessionDir));
    assert(strcmp(resumed.diagnosticDir,info.diagnosticDir));
    second=retry(model=name,device="cpu",start=false);
    assert(~strcmp(second.sessionDir,info.sessionDir),'New training must keep previous results.');
    assert(isfile(fullfile(info.sessionDir,'model.json')));
end
rejected=false;
try, retry(model="missing_model",start=false); catch e, rejected=strcmp(e.identifier,'Modular:UnknownModel'); end
assert(rejected);
rejected=false;
try, retry(resume=info.sessionDir,model="ppo_lstm128",start=false); catch e, rejected=strcmp(e.identifier,'Modular:ModelMismatch'); end
assert(rejected);
% Simulate legacy control files that only define diagnosticRoot.
file=fullfile(info.sessionDir,'control.json');
cfg=jsondecode(fileread(file)); cfg=rmfield(cfg,'diagnosticDir');
cfg.diagnosticRoot=fullfile(root,'training_diagnostics');
fid=fopen(file,'w'); fprintf(fid,'%s',jsonencode(cfg)); fclose(fid);
legacy=retry(resume=info.sessionDir,start=false);
[~,tag]=fileparts(info.sessionDir);
assert(strcmp(legacy.diagnosticDir,fullfile(cfg.diagnosticRoot,tag)));
fprintf('PASS: model folders, separate runs, source-only snapshots, resume, legacy diagnostics, invalid models.\n');
end
