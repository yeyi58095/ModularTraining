function test_sac_paper_probe()
% Archived child 1600/1700 copied to isolated fixture; inference only.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'runtime'));
f=jsondecode(fileread(fullfile(root,'tests','output','sac-paper-probe-fixture.json')));session=string(f.folder);
before=cell(1,2);episodes=[1600 1700];
for k=1:2
    before{k}=checkpointreview.sha256(fullfile(session,'checkpoints',sprintf('Agent%d.mat',episodes(k))));
    r=trainingtools.inspect_sac_checkpoint(session,episodes(k));assert(r.source_unchanged && strcmp(r.sha256,before{k}));
end
shared=trainingtools.probe_sac_mlp_checkpoints(session,episodes);
curves=trainingtools.probe_sac_action_values(session,fullfile(shared,'shared-inputs.mat'),episodes);
for k=1:2
    r=jsondecode(fileread(fullfile(curves,sprintf('episode%d.json',episodes(k)))));
    assert(r.weights_unchanged && r.source_unchanged && strcmp(r.sha256,before{k}));
    assert(numel(r.indices)==16 && numel(r.action_grid)==33 && numel(r.q_values)==16*33*2);
    assert(strcmp(before{k},checkpointreview.sha256(fullfile(session,'checkpoints',sprintf('Agent%d.mat',episodes(k))))));
end
trainingcurriculum.write_json(fullfile(root,'tests','output','sac-paper-probe-results.json'), ...
    struct('shared',shared,'curves',curves,'scope','Real archived models, CPU inference only; no train/sim'));
fprintf('PAPER_PROBE_OK: actual paper64 models, 2 replay prefixes and 16x33x2 Q grid, source/weights unchanged.\n');
end
