function overrides = training(cfg,overrides)
% 模型適配層：從 run 的 model.json 及 model_source 建立 agent factory 與 validator。
% 輸入 cfg 與 overrides；回傳補上模型建構／驗證函式的 overrides，環境仍由共用 runtime 執行。
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
