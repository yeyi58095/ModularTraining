function checkpoint_save_final(filename, Agent_Stage2, training_stage2)
% 段末 checkpoint 發布：將 agent 與對應訓練歷史一起寫入暫存 MAT，再替換正式檔。
% 輸入 filename、Agent_Stage2、training_stage2；清理失敗暫存，避免讀者取得半寫入的 Final。
% Publish agent and its matching history together, after a complete write.
    temporary = [tempname(fileparts(filename)) '.mat'];
    guard = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
    save(temporary,'Agent_Stage2','training_stage2','-v7.3');
    [ok,message] = movefile(temporary,filename,'f');
    assert(ok,'Checkpoint:FinalPublish','%s',message);
end
function removeTemporary(filename)
% 只清理本次尚未發布的暫存 MAT，不刪除正式 checkpoint。
    if isfile(filename), delete(filename); end
end
