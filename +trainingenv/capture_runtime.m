function manifest=capture_runtime(runtime,sessionDir)
% Recovery compatibility: freeze CURRENT runtime, never infer parent history.
entries=[dir(fullfile(runtime,'FAFA_Simulation.slx'));dir(fullfile(runtime,'*.mat'));dir(fullfile(runtime,'*.sldd'))];
files=struct('name',{},'sha256',{});
for i=1:numel(entries)
    files(i)=struct('name',entries(i).name, ...
        'sha256',checkpointreview.sha256(fullfile(runtime,entries(i).name)));
end
modelHash=checkpointreview.sha256(fullfile(runtime,'FAFA_Simulation.slx'));
manifest=struct('schema_version',1,'id',['legacy_prepared_' modelHash(1:12)],'model_file','FAFA_Simulation.slx', ...
    'provenance','Current runtime captured for legacy recovery preparation; not historical evidence.', ...
    'files',files);
sourceManifest=fullfile(sessionDir,'environment_source.json');
trainingcurriculum.write_json(sourceManifest,manifest);
trainingenv.snapshot(sourceManifest,runtime,sessionDir);
end
