function test_history_candidate()
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
assert(~bdIsLoaded('FAFA_Simulation'));load_system(fullfile(root,'runtime','FAFA_Simulation.slx'));
guard=onCleanup(@() close_system('FAFA_Simulation',0));
c=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function12');
original=fileread(fullfile(root,'tests','fixtures','guidance_before_progress.m.txt'));
original=strrep(original,sprintf('\r\n'),newline);
modified=checkpointreview.history_candidate(original);
assert(strcmp(strrep(c.Script,sprintf('\r\n'),newline),modified), ...
    'Test:ProductionDrift','Production guidance differs from tested fix.');clear guard;
folder=tempname;mkdir(folder);old=path;cleanup=onCleanup(@()path(old)); %#ok<NASGU>
for entry={{'history_base',original},{'history_fixed',modified}}
 item=entry{1};fid=fopen(fullfile(folder,[item{1} '.m']),'w');
 fprintf(fid,'%s',strrep(item{2},'guidance_law(',[item{1} '(']));fclose(fid);
end
addpath(folder);
p=[100 100 70;200 100 70];
[e0,n0,d0]=history_base(100,240,0,15,p,100);
[e1,n1,d1]=history_fixed(100,240,0,15,p,100);
assert(d0>10 && abs(d1)<1e-9 && e0==e1 && n0==n1);
[~,~,d1]=history_fixed(105,240,0,15,p,100);assert(abs(d1-5)<1e-9);
% Ordinary inside-path geometry and targets remain unchanged.
[e0,n0,d0]=history_base(105,150,0,15,p,100);
[e1,n1,d1]=history_fixed(105,150,0,15,p,100);
assert(isequal([e0 n0 d0],[e1 n1 d1]));
try
 checkpointreview.history_candidate(modified);error('Test:ExpectedError','Expected drift refusal');
catch err
 assert(strcmp(err.identifier,'Evaluation:GuidanceDrift'));
end
fprintf('PASS valid historical extent, unchanged targets, inside geometry, duplicate refusal.\n');
end
