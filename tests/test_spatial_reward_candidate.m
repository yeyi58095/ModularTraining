function test_spatial_reward_candidate()
% Unit, monotonicity, unchanged control penalties and no bonus discontinuity.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
d=[0;5;10;30;50];parts=zeros(5,10);parts(:,10)=-0.1;
for w=[.2 .4 .6]
    [r,t]=checkpointreview.spatial_reward_candidate(parts,d,w);
    assert(all(diff(r)<0));
    assert(abs(t(3,8)-.1)<1e-12 && abs(t(1,8)-.15)<1e-12);
    assert(isequal(t(:,[2:7 9:10]),parts(:,[2:7 9:10])));
    [r0,~]=checkpointreview.spatial_reward_candidate(zeros(5,10),d,w);
    assert(max(abs(r0-r-.1))<1e-12);
end
% No reward jump on crossing the physical 10 m bonus boundary.
r=checkpointreview.spatial_reward_candidate(zeros(3,10),[10-1e-8;10;10+1e-8]);
assert(all(diff(r)<0) && max(abs(diff(r)))<1e-8);
% No curvature relief or old target-distance inputs exist in this candidate.
try
    checkpointreview.spatial_reward_candidate(zeros(1,10),-1);
    error('Test:ExpectedFailure','Negative distance accepted.');
catch err
    assert(~strcmp(err.identifier,'Test:ExpectedFailure'));
end
try
    checkpointreview.spatial_reward_candidate(zeros(2,10),1);
    error('Test:ExpectedFailure','Shape mismatch accepted.');
catch err
    assert(strcmp(err.identifier,'RewardCalibration:Shape'));
end
fprintf('PASS spatial reward candidate: physical units, monotonicity, continuous boundary, retained penalties, invalid inputs.\n');
end
