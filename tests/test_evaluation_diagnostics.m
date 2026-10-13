function test_evaluation_diagnostics()
% 訊號記錄 A/B 測試：對同一情境做兩次短 CPU sim，比較無記錄與診斷記錄的 reward／觀測／動作。
% 確認週期 window 訊號與原 SLX 雜湊；不執行訓練或保存正式模型修改。
% Real paired pure simulations, including the first periodic path update.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
receipt=jsondecode(fileread(fullfile(root,'tests','output','curriculum-smoke-latest.json')));
model=fullfile(root,'runtime','FAFA_Simulation.slx'); before=checkpointreview.sha256(model);
plain=compare_training_checkpoints(receipt.sessionDir,episodes=3,includeLatest=false, ...
    stages=3,seeds=205,maxSteps=110);
logged=compare_training_checkpoints(receipt.sessionDir,episodes=3,includeLatest=false, ...
    stages=3,seeds=205,maxSteps=110,diagnostics=true);
a=load(fullfile(plain.outputDir,plain.results{1}.trace));
b=load(fullfile(logged.outputDir,logged.results{1}.trace));
assert(isequaln(a.experience.Reward.Data,b.experience.Reward.Data));
assert(isequaln(a.experience.Observation,b.experience.Observation));
assert(isequaln(a.experience.Action,b.experience.Action));
assert(b.diagnostics.numElements>=14);
valid=b.diagnostics.getElement('window_valid').Values;
assert(any(valid.Time>=9.9 & logical(valid.Data(:))));
assert(~isempty(b.diagnostics.getElement('planned_path').Values));
assert(strcmp(before,checkpointreview.sha256(model)) && ~bdIsLoaded('FAFA_Simulation'));
fprintf('PASS: diagnostic logging matches baseline experience exactly through 110 steps; original SLX unchanged.\n');
end
