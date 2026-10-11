function test_endpoint_candidate()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
model=fullfile(root,'runtime','FAFA_Simulation.slx'); before=checkpointreview.sha256(model);
assert(~bdIsLoaded('FAFA_Simulation')); load_system(model);
guard=onCleanup(@() close_system('FAFA_Simulation',0));
chart=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function12');
production=strrep(chart.Script,sprintf('\r\n'),newline);
original=fileread(fullfile(root,'tests','fixtures','guidance_before_endpoint.m.txt'));
original=strrep(original,sprintf('\r\n'),newline);
modified=checkpointreview.endpoint_candidate(original);
modified2=checkpointreview.endpoint_candidate(original,true);
assert(strcmp(strtrim(production),strtrim(modified2)),'Production guidance differs from validated v2.');
try
    checkpointreview.endpoint_candidate(production,true);
    error('Test:ExpectedRejection','Expected duplicate patch rejection.');
catch err
    assert(strcmp(err.identifier,'Evaluation:AlreadyApplied'));
end
clear guard;
folder=tempname; mkdir(folder); old=path; cleanup=onCleanup(@() path(old)); %#ok<NASGU>
for entry={{'guidance_base',original},{'guidance_candidate',modified},{'guidance_candidate_v2',modified2}}
    item=entry{1}; fid=fopen(fullfile(folder,[item{1} '.m']),'w','n','UTF-8');
    fprintf(fid,'%s',strrep(item{2},'guidance_law(',[item{1} '('])); fclose(fid);
end
addpath(folder);
short=[0 0 70;100 0 70];
[base,~,d0]=guidance_base(0,110,0,15,short,100);
[candidate,~,d1,~,h]=guidance_candidate(0,110,0,15,short,100);
assert(base==100 && candidate==160 && d0==d1 && h==0);
[e,n,d]=guidance_candidate(10,90,0,15,short,100);
assert(e==140 && n==0 && abs(d-10)<1e-10);
long=[(0:10:300)' zeros(31,1) ones(31,1)*70];
[e0,n0,d0]=guidance_base(5,20,0,15,long,100);
[e1,n1,d1]=guidance_candidate(5,20,0,15,long,100);
assert(isequal([e0 n0 d0],[e1 n1 d1]));
% V1 reverts to old endpoint outside the bounding box; V2 retains lookahead.
clear guidance_candidate guidance_candidate_v2
[e0,~,d0]=guidance_candidate(0,140,0,15,short,100);
[e2,n2,d2]=guidance_candidate_v2(0,140,0,15,short,100);
assert(e0==100 && e2==190 && n2==0 && d0==d2);
% Check boundary continuity in target, without changing distance calculation.
[left,~]=guidance_candidate_v2(5,129.99,0,15,short,100);
[right,~]=guidance_candidate_v2(5,130.01,0,15,short,100);
assert(abs((right-left)-.02)<1e-10);
% Large lateral deviations and points before path start retain old behavior.
for position={[140 40],[-40 0]}
    p=position{1};
    [e0,n0,d0]=guidance_candidate(p(2),p(1),0,15,short,100);
    [e2,n2,d2]=guidance_candidate_v2(p(2),p(1),0,15,short,100);
    assert(isequal([e0 n0 d0],[e2 n2 d2]));
end
% Rotation: vertical path endpoint overshoot must extend north, not east.
vertical=[0 0 70;0 100 70];
[e2,n2]=guidance_candidate_v2(140,5,pi/2,15,vertical,100);
assert(e2==0 && n2==190);
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
r=compare_training_checkpoints(receipt.sessionDir,episodes=3,includeLatest=false, ...
    stages=3,seeds=205,maxSteps=110,diagnostics=true);
assert(strcmp(r.status,'complete'));
assert(strcmp(before,checkpointreview.sha256(model)));
fprintf('PASS endpoint geometry, production v2 script equality, CPU sim 110 steps; source model unchanged.\n');
end
