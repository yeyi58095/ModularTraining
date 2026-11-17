function test_sac_pilot_exploration()
% Fake evaluator only: bounded calls, completed rerun, mismatch/interruption guard.
root=fileparts(fileparts(mfilename('fullpath')));
f=jsondecode(fileread(fullfile(root,'tests','output','exploration-check-fixture.json')));
old=path;cwd=pwd;c=onCleanup(@() restore(old,cwd)); %#ok<NASGU>
cd(f.root);addpath(f.root,'-begin');
bundle=trainingtools.review_sac_pilot_exploration();
r=jsondecode(fileread(fullfile(bundle,'review.json')));assert(strcmp(r.status,'complete') && numel(r.completed)==3);
a=jsondecode(fileread(fullfile(bundle,'comparison.json')));assert(numel(a)==24);
count=readlines(fullfile(f.root,'calls.txt'));assert(numel(count(strlength(count)>0))==3);
trainingtools.review_sac_pilot_exploration();
assert(isequal(count,readlines(fullfile(f.root,'calls.txt'))),'Completed operation repeated simulations.');
% Only the isolated fixture ledger is removed to exercise a second failure case.
delete(fullfile(bundle,'review.json'));fid=fopen(fullfile(f.root,'FAIL'),'w');fclose(fid);
failed=false;try,trainingtools.review_sac_pilot_exploration();catch e,failed=strcmp(e.identifier,'ExplorationReview:Environment');end
assert(failed,'Environment mismatch accepted.');
count=readlines(fullfile(f.root,'calls.txt'));
failed=false;try,trainingtools.review_sac_pilot_exploration();catch e,failed=strcmp(e.identifier,'ExplorationReview:Interrupted');end
assert(failed && isequal(count,readlines(fullfile(f.root,'calls.txt'))),'Interrupted operation repeated simulations.');
fprintf('EXPLORATION_CHECK_OK: 3x8 bounded fake simulations, complete rerun skipped, environment mismatch and automatic repeat rejected.\n');
end
function restore(p,d),path(p);cd(d);end
