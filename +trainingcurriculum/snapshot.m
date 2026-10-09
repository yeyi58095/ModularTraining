function snapshot(plan,sourceFile,sessionDir)
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
