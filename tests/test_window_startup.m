function test_window_startup()
% window 初始化測試：從實際 SLX 抽出 chart 函式，驗證首次及週期 valid 與短路徑拒絕。
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
script=strrep(chart.Script,'= WindowManager(', '= startup_window_fixture(');
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
fprintf('PASS embedded WindowManager: ready on call 1, periodic calls 100/200, short path rejected.\n');
end
