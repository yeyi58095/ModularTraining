function output=audit_sac_wind_history()
% Read saved SAC learning state for the six evaluated checkpoints.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path; cleanup=onCleanup(@() path(oldPath));
addpath(root,fullfile(root,'runtime'));
session=string(strtrim(fileread(fullfile(root,'artifacts','sac-weak-wind-1000-run.txt'))));
[~,id]=fileparts(session);
assert(id=="20261105_210649_recovery_tpb199bcee",'SAC:Source','Unexpected weak-wind run.');
bundle=fullfile(root,'artifacts','packages',"sac-wind-history-"+id);
manifest=jsondecode(fileread(fullfile(bundle,'manifest.json')));
assert(strcmp(manifest.status,'complete') && strcmp(manifest.session,session), ...
    'SAC:Bundle','Complete the frozen history review first.');
% Inspect helper locks the paused run and verifies its checkpoint SHA again.
output=fullfile(bundle,'checkpoint_audit');
if ~isfolder(output), mkdir(output); end
lock=System.IO.File.Open(char(fullfile(output,'audit.lock')), ...
    System.IO.FileMode.OpenOrCreate,System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
unlock=onCleanup(@() lock.Dispose());
state=struct('status','running','completed_episodes',[],'scope','Saved-state audit; no training or simulation.');
trainingcurriculum.write_json(char(fullfile(output,'status.json')),state);
try
    for ep=1000:100:1500
        previous=jsondecode(fileread(fullfile(bundle,sprintf('episode_%d',ep),'complete.json')));
        report=trainingtools.inspect_sac_checkpoint(session,ep);
        assert(strcmp(report.sha256,previous.checkpoint_sha256), ...
            'SAC:Changed','Checkpoint differs from the evaluated source.');
        trainingcurriculum.write_json(char(fullfile(output,sprintf('checkpoint_%d.json',ep))),report);
        state.completed_episodes(end+1)=ep;
        trainingcurriculum.write_json(char(fullfile(output,'status.json')),state);
    end
    state.status='complete';
catch err
    state.status='failed'; state.error=getReport(err,'extended','hyperlinks','off');
    trainingcurriculum.write_json(char(fullfile(output,'status.json')),state);
    rethrow(err);
end
trainingcurriculum.write_json(char(fullfile(output,'status.json')),state);
fprintf('Checkpoint audit complete. Package this directory:\n%s\n',bundle);
end
