function bundle=probe_sac_actor_pilot()
% Inspect the completed two-arm pilot. No train, sim, pool, or retry.
root=fileparts(fileparts(mfilename('fullpath')));old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
addpath(root,fullfile(root,'runtime'));
pilot=fullfile(root,'artifacts','packages','sac-actor-pilot-20261116');
bundle=fullfile(root,'artifacts','packages','sac-actor-pilot-probe-20261117');
if ~isfolder(bundle),mkdir(bundle);end
lock=System.IO.File.Open(fullfile(bundle,'review.lock'),System.IO.FileMode.OpenOrCreate, ...
    System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);unlock=onCleanup(@() lock.Dispose()); %#ok<NASGU>
state=struct('status','running','scope','Read-only paired 1600/1700 diagnosis within each pilot arm. No training or simulation.');
write(fullfile(bundle,'review.json'),state);
try
    ledger=read(fullfile(pilot,'review.json'));protocol=read(fullfile(pilot,'protocol.json'));
    assert(strcmp(ledger.status,'complete') && protocol.episodes_per_branch==100, ...
        'PilotProbe:Incomplete','Complete the actor pilot first.');
    children=ledger.children;if iscell(children),children=[children{:}];end
    assert(numel(children)==2 && isequal(sort({children.label}),sort({'baseline','actor_half'})), ...
        'PilotProbe:Children','Unexpected pilot arms.');
    for label={'baseline','actor_half'}
        arm=label{1};item=children(strcmp({children.label},arm));
        % Resolve beneath THIS checkout; never follow another machine's drive.
        parts=regexp(item.session,'[\\/]','split');id=parts{end};
        assert(~isempty(regexp(id,'^2026111[67]_\d{6}_recovery_tp[0-9a-f]+$','once')), ...
            'PilotProbe:Path','Unexpected run identity.');
        session=fullfile(root,'experiments','sac_random_route_v1','runs',id);
        s=read(fullfile(session,'status.json'));m=read(fullfile(session,'model.json'));
        recovery=read(fullfile(session,'recovery.json'));
        assert(strcmp(s.state,'paused') && strcmp(m.name,'sac_paper64') && ...
            strcmp(recovery.parent_sha256,protocol.source_sha256) && recovery.parent_episode==1600, ...
            'PilotProbe:Source','Unexpected source or active run.');
        evaluation=read(fullfile(pilot,[arm '_evaluation'],'evaluation.json'));
        cp=evaluation.checkpoints;if iscell(cp),cp=[cp{:}];end
        assert(strcmp(evaluation.status,'complete') && evaluation.weights_unchanged && ...
            numel(cp)==1 && cp.episode==1700,'PilotProbe:Evaluation','Unexpected frozen result.');
        % Probe immutable copies: final and periodic MAT serialization may differ.
        original=session;
        sourceLock=System.IO.File.Open(fullfile(original,'supervisor.lock'),System.IO.FileMode.Open, ...
            System.IO.FileAccess.ReadWrite,System.IO.FileShare.None);
        sourceUnlock=onCleanup(@() sourceLock.Dispose());
        s=read(fullfile(original,'status.json'));assert(strcmp(s.state,'paused'),'PilotProbe:Active','Run became active.');
        session=tempname(fullfile(root,'artifacts'));mkdir(session);mkdir(fullfile(session,'checkpoints'));
        sourceFiles={fullfile(original,'checkpoints','Agent1600.mat'),fullfile(pilot,arm,'Agent_Final.mat')};
        expectedHashes={recovery.child_checkpoint_sha256,cp.sha256};
        for j=1:2
            assert(strcmp(checkpointreview.sha256(sourceFiles{j}),expectedHashes{j}),'PilotProbe:Changed','Wrong source model.');
            destination=fullfile(session,'checkpoints',sprintf('Agent%d.mat',1500+j*100));
            copyfile(sourceFiles{j},destination);
            assert(strcmp(checkpointreview.sha256(destination),expectedHashes{j}) && ...
                strcmp(checkpointreview.sha256(sourceFiles{j}),expectedHashes{j}),'PilotProbe:Copy','Copy verification failed.');
        end
        copyfile(fullfile(original,'model.json'),fullfile(session,'model.json'));
        write(fullfile(session,'status.json'),struct('state','paused'));
        f=fopen(fullfile(session,'supervisor.lock'),'w');assert(f>=0);fclose(f);
        clear sourceUnlock
        target=fullfile(bundle,arm);if ~isfolder(target),mkdir(target);end
        write(fullfile(target,'provenance.json'),struct('original_session',original, ...
            'source_files',{sourceFiles},'sha256',{expectedHashes},'isolated_snapshot',session));
        for ep=[1600 1700]
            report=trainingtools.inspect_sac_checkpoint(string(session),ep);
            expected=recovery.child_checkpoint_sha256;if ep==1700,expected=cp.sha256;end
            assert(strcmp(report.sha256,expected),'PilotProbe:Changed','Saved model differs from evaluated pilot.');
            write(fullfile(target,sprintf('state_%d.json',ep)),report);
        end
        out=trainingtools.probe_sac_mlp_checkpoints(string(session),[1600 1700]);
        shared=fullfile(target,'shared_inputs');if ~isfolder(shared),mkdir(shared);end
        copyfile(fullfile(out,'*'),shared);
        out=trainingtools.probe_sac_action_values(string(session), ...
            string(fullfile(shared,'shared-inputs.mat')),[1600 1700]);
        action=fullfile(target,'action_values');if ~isfolder(action),mkdir(action);end
        copyfile(fullfile(out,'*'),action);
        for ep=[1600 1700]
            audit=read(fullfile(target,sprintf('state_%d.json',ep)));
            a=read(fullfile(shared,sprintf('episode%d.json',ep)));
            b=read(fullfile(action,sprintf('episode%d.json',ep)));
            assert(a.source_unchanged && b.source_unchanged && b.weights_unchanged && ...
                strcmp(audit.sha256,a.sha256) && strcmp(a.sha256,b.sha256) && ...
                strcmp(b.sha256,checkpointreview.sha256(fullfile(session,'checkpoints',sprintf('Agent%d.mat',ep)))), ...
                'PilotProbe:Changed','Source changed during diagnosis.');
        end
    end
    state.status='complete';
catch err
    state.status='failed';state.error=getReport(err,'extended','hyperlinks','off');
    write(fullfile(bundle,'review.json'),state);rethrow(err);
end
write(fullfile(bundle,'review.json'),state);
fprintf('Pilot diagnosis complete. Keep all training paused. Bundle: %s\n',bundle);
end
function r=read(f),r=jsondecode(fileread(f));end
function write(f,r),trainingcurriculum.write_json(f,r);end
