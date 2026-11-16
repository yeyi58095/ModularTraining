function bundle=probe_sac_child()
% Read-only 1600/1700 state and shared-input diagnosis. Never train or sim.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
session=fullfile(root,'experiments','sac_random_route_v1','runs','20261114_211021_recovery_tp4c32126b');
history=fullfile(root,'artifacts','packages','sac-child-history-20261116');
bundle=fullfile(root,'artifacts','packages','sac-child-probe-20261116');
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
state=struct('status','running','session',session,'episodes',[1600 1700], ...
    'scope','Saved state and identical replay inputs; no training/simulation or automatic parameter changes.');
write(fullfile(bundle,'review.json'),state);
try
    m=read(fullfile(session,'model.json'));s=read(fullfile(session,'status.json'));
    assert(strcmp(m.name,'sac_paper64') && strcmp(s.state,'paused'),'ChildProbe:Source','Expected paused paper64 child.');
    h=read(fullfile(history,'review.json'));
    assert(strcmp(h.status,'complete') && strcmp(h.session,session),'ChildProbe:History','Complete this child history review first.');
    for ep=[1600 1700]
        report=trainingtools.inspect_sac_checkpoint(string(session),ep);
        previous=read(fullfile(history,sprintf('episode_%d',ep),'complete.json'));
        assert(strcmp(report.sha256,previous.checkpoint_sha256),'ChildProbe:Changed','Checkpoint differs from evaluated model.');
        write(fullfile(bundle,sprintf('state_%d.json',ep)),report);
    end
    out=trainingtools.probe_sac_mlp_checkpoints(string(session),[1600 1700]);
    target=fullfile(bundle,'shared_inputs');if ~isfolder(target),mkdir(target);end
    copyfile(fullfile(out,'*'),target);
    inputFile=fullfile(bundle,'shared_inputs','shared-inputs.mat');
    out=trainingtools.probe_sac_action_values(string(session),string(inputFile),[1600 1700]);
    target=fullfile(bundle,'action_values');if ~isfolder(target),mkdir(target);end
    copyfile(fullfile(out,'*'),target);
    for ep=[1600 1700]
        baseline=read(fullfile(bundle,sprintf('state_%d.json',ep)));
        shared=read(fullfile(bundle,'shared_inputs',sprintf('episode%d.json',ep)));
        action=read(fullfile(bundle,'action_values',sprintf('episode%d.json',ep)));
        assert(strcmp(baseline.sha256,shared.sha256) && strcmp(shared.sha256,action.sha256) && ...
            strcmp(action.sha256,checkpointreview.sha256(fullfile(session,'checkpoints',sprintf('Agent%d.mat',ep)))), ...
            'ChildProbe:Changed','Source changed between probes.');
    end
    state.status='complete';
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');
    write(fullfile(bundle,'review.json'),state);rethrow(err);
end
write(fullfile(bundle,'review.json'),state);
fprintf('Complete. Keep training paused. Bundle: %s\n',bundle);
end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
