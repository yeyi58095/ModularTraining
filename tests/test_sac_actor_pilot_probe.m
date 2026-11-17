function test_sac_actor_pilot_probe()
% Isolated orchestration with archived real agents. Inference only.
root=fileparts(fileparts(mfilename('fullpath')));
config=jsondecode(fileread(fullfile(root,'tests','output','actor-pilot-probe-fixture.json')));
old=path;c=onCleanup(@() path(old)); %#ok<NASGU>
oldFolder=pwd;folderCleanup=onCleanup(@() cd(oldFolder));cd(config.root); %#ok<NASGU>
addpath(config.root,'-begin');
out=trainingtools.probe_sac_actor_pilot();
r=jsondecode(fileread(fullfile(out,'review.json')));assert(strcmp(r.status,'complete'));
for arm={'baseline','actor_half'}
    for ep=[1600 1700]
        s=jsondecode(fileread(fullfile(out,arm{1},sprintf('state_%d.json',ep))));
        q=jsondecode(fileread(fullfile(out,arm{1},'action_values',sprintf('episode%d.json',ep))));
        assert(s.source_unchanged && q.source_unchanged && q.weights_unchanged && strcmp(s.sha256,q.sha256));
    end
end
% A changed evaluated final must fail before probing that arm.
file=fullfile(config.root,'artifacts','packages','sac-actor-pilot-20261116','baseline_evaluation','evaluation.json');
evaluation=jsondecode(fileread(file));evaluation.checkpoints.sha256=repmat('0',1,64);
trainingcurriculum.write_json(file,evaluation);
failed=false;try,trainingtools.probe_sac_actor_pilot();catch e,failed=strcmp(e.identifier,'PilotProbe:Changed');end
assert(failed,'Tampered model reference was not rejected.');
fprintf('PILOT_PROBE_OK: two archived arms, immutable copies, CPU inference, hash mismatch rejected; no train/sim/pool.\n');
end
