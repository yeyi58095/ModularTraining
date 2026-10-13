function test_progress_window_candidate()
% Exercise local, monotonic spatial progress without running a simulation.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
assert(~bdIsLoaded('FAFA_Simulation'));load_system(fullfile(root,'runtime','FAFA_Simulation.slx'));
guard=onCleanup(@() close_system('FAFA_Simulation',0));
c=find(sfroot,'-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function3');
original=fileread(fullfile(root,'tests','fixtures','window_before_progress.m.txt'));
script=checkpointreview.progress_window_candidate(original);
assert(strcmp(c.Script,script),'Test:ProductionDrift','Production window differs from tested candidate.');clear guard;
folder=tempname;mkdir(folder);old=path;cleanup=onCleanup(@()path(old)); %#ok<NASGU>
fid=fopen(fullfile(folder,'progress_fixture.m'),'w');
fprintf(fid,'%s',strrep(script,'= WindowManager(', '= progress_fixture('));fclose(fid);addpath(folder);
p=[(0:599)'*1.5 zeros(600,2)];v=repmat([15 0 0],600,1);
[w,~,flag]=progress_fixture(p,v,100,0,0);assert(flag && isequal(w,p(1:100,:)));
for k=1:200
 [w,~,flag]=progress_fixture(p,v,100,0,0);
 assert(~flag && isequal(w,p(1:100,:))); % Time alone must not advance route.
end
[w,~,flag]=progress_fixture(p,v,100,75,0);assert(~flag && isequal(w,p(1:100,:)));
[w,~,flag]=progress_fixture(p,v,100,88.5,0);assert(flag && isequal(w,p(100:199,:)));
[w,~,flag]=progress_fixture(p,v,100,30,0);assert(~flag && isequal(w,p(100:199,:)));
% A distant later branch cannot jump over the bounded search neighbourhood.
[w,~,~]=progress_fixture(p,v,100,800,0);assert(isequal(w,p(199:298,:)));
for k=1:10, [w,~,~]=progress_fixture(p,v,100,1000,0);end
assert(isequal(w,p(496:595,:))); % Only complete contiguous chunks, no overrun.
clear progress_fixture
[w,~,flag]=progress_fixture(p(1:50,:),v(1:50,:),100,0,0);
assert(~flag && all(w==0,'all'));
try
 checkpointreview.progress_window_candidate(script);error('Test:ExpectedError','Expected drift refusal');
catch err
 assert(strcmp(err.identifier,'Evaluation:WindowDrift'));
end
fprintf('PASS spatial progress, contiguous previews, no time drift, bounded search, end and short route.\n');
end
