function [modelFile,manifest]=resolve(sessionDir)
% Bound runs never fall back to an editable shared model.
file=fullfile(sessionDir,'environment.json');
assert(isfile(file),'Environment:Unbound', ...
    'Run has no environment snapshot. Before updating the remote project, run preserve_training_environment.ps1 against its stopped run and current runtime.');
assert(~isfolder(fullfile(sessionDir,'environment.preparing')), ...
    'Environment:Incomplete','Incomplete environment preparation exists.');
manifest=trainingenv.verify(file,fullfile(sessionDir,'environment'));
modelFile=fullfile(sessionDir,'environment',manifest.model_file);
end
