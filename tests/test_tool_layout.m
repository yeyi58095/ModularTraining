function test_tool_layout()
% New package resolution from outside the checkout; no train/sim or real run creation.
root=fileparts(fileparts(mfilename('fullpath')));
oldPath=path;oldFolder=pwd;guard=onCleanup(@()restore(oldPath,oldFolder)); %#ok<NASGU>
addpath(root);cd(tempdir);
files=dir(fullfile(root,'+trainingtools','*.m'));
for k=1:numel(files)
    [~,name]=fileparts(files(k).name);
    assert(strcmp(which(['trainingtools.' name]),fullfile(files(k).folder,files(k).name)));
end
before=dir(fullfile(root,'experiments','progressive_v2','runs'));
planFile=fullfile(root,'experiments','progressive_v2','curriculum.json');
beforeSha=checkpointreview.sha256(planFile);
inputs=trainingtools.prepare_progressive_v2_training();
assert(strcmp(inputs.planFile,planFile));
check=trainingtools.preflight_round3();
assert(check.freshAgent && ~check.runCreated && ~check.trainingStarted && ~check.config.start);
after=dir(fullfile(root,'experiments','progressive_v2','runs'));
assert(isequal({before.name},{after.name}));
assert(strcmp(beforeSha,checkpointreview.sha256(planFile)));
assert(strcmp(check.curriculumSha256,beforeSha));
fprintf('PASS tool package resolution, external CWD, round3 preflight, unchanged curriculum/run list.\n');
end
function restore(p,f)
cd(f);path(p);
end
