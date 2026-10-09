function overrides = training(cfg,overrides)
% Model adapter; environment execution stays in the shared FAFA trainer.
manifest = fullfile(cfg.sessionDir,'model.json');
spec = jsondecode(fileread(manifest));
source = fullfile(cfg.sessionDir,'model_source');
assert(isfolder(fullfile(source,'+trainingmodels')), ...
    'Modular:MissingSnapshot','Model source snapshot is missing.');
addpath(source,'-begin');
overrides.agentFactory = @(obs,act,device) trainingmodels.build_agent(spec,obs,act,device);
overrides.agentValidator = @(agent) trainingmodels.validate_agent(agent,spec);
fprintf('Model profile: %s; algorithm: %s; LSTM units: %d\n',spec.name,spec.algorithm,spec.lstmUnits);
end
