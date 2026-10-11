function test_endpoint_candidate()
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
model=fullfile(root,'runtime','FAFA_Simulation.slx'); before=checkpointreview.sha256(model);
assert(~bdIsLoaded('FAFA_Simulation')); load_system(model);
guard=onCleanup(@() close_system('FAFA_Simulation',0));
chart=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function12');
original=chart.Script; modified=checkpointreview.endpoint_candidate(original);
clear guard;
folder=tempname; mkdir(folder); old=path; cleanup=onCleanup(@() path(old)); %#ok<NASGU>
for entry={{'guidance_base',original},{'guidance_candidate',modified}}
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
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
r=compare_training_checkpoints(receipt.sessionDir,episodes=3,includeLatest=false, ...
    stages=3,seeds=205,maxSteps=110,diagnostics=true,guidanceVariant="endpoint_lookahead");
assert(strcmp(r.status,'complete') && isfield(r,'candidate_script_sha256'));
assert(strcmp(before,checkpointreview.sha256(model)));
fprintf('PASS endpoint geometry, unchanged nonterminal target, candidate CPU sim 110 steps; source model unchanged.\n');
end
