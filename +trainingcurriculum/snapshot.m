function snapshot(plan,sourceFile,sessionDir)
% 課程快照建立：複製各 MAT 到 run/curriculum_assets，重寫副本的相對路徑並驗證。
% 只寫新 run 的課程副本；共享 JSON 與來源 MAT 保持原樣，使後續 attempts 使用固定輸入。
% Make future attempts independent of the user's editable plan and MAT inputs.
assets=fullfile(sessionDir,'curriculum_assets');
for i=1:numel(plan.stages)
    t=plan.stages{i}.trajectory;
    if strcmp(t.type,'mat')
        if ~isfolder(assets), mkdir(assets); end
        name=sprintf('stage%03d.mat',i);
        copyfile(fullfile(fileparts(sourceFile),t.file),fullfile(assets,name));
        plan.stages{i}.trajectory.file=['curriculum_assets/' name];
    end
end
file=fullfile(sessionDir,'curriculum.json');
trainingcurriculum.write_json(file,plan);
trainingcurriculum.load_plan(file,true); % Validate the copied data too.
end
