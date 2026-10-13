function test_window_startup()
% 舊時序 window 的初始化回歸；正式空間 window 另驗證其首次 valid 與進度更新。
% 只呼叫抽出的純函式，不啟動 Simulink 模擬或訓練，也不保存 SLX。
% Execute the actual embedded function without running a Simulink simulation.
root=fileparts(fileparts(mfilename('fullpath')));
assert(~bdIsLoaded('FAFA_Simulation'),'Close FAFA_Simulation before this test.');
load_system(fullfile(root,'runtime','FAFA_Simulation.slx'));
cleanup=onCleanup(@()close_system('FAFA_Simulation',0)); %#ok<NASGU>
sf=sfroot;
chart=sf.find('-isa','Stateflow.EMChart','Path','FAFA_Simulation/OBSERVATION/MATLAB Function3');
assert(isscalar(chart));
folder=tempname(fullfile(root,'tests','output')); mkdir(folder);
oldPath=path; pathGuard=onCleanup(@()path(oldPath)); %#ok<NASGU>
script=fileread(fullfile(root,'tests','fixtures','window_before_progress.m.txt'));
script=strrep(script,'= WindowManager(', '= startup_window_fixture(');
fid=fopen(fullfile(folder,'startup_window_fixture.m'),'w','n','UTF-8');
fprintf(fid,'%s',script); fclose(fid); addpath(folder);
p=[(0:599)'*1.5 zeros(600,2)]; v=repmat([15 0 0],600,1);
flags=false(1,201);
for k=1:201
    [window,~,flags(k)]=startup_window_fixture(p,v,100,0,0);
    assert(isequal(window,p(k:k+99,:)));
end
assert(isequal(find(flags),[1 100 200]));
clear startup_window_fixture
% A path shorter than the requested window must still be rejected.
[~,~,valid]=startup_window_fixture(p(1:50,:),v(1:50,:),100,0,0);
assert(~valid);
clear startup_window_fixture
fprintf('PASS historical timed WindowManager: calls 1/100/200, short path rejected.\n');
clear cleanup;
test_progress_window_candidate();
end
