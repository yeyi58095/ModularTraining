function manifest=snapshot(sourceManifest,sourceDir,sessionDir)
% Caller owns the run lock (or an unpublished new run). Commit marker last.
manifest=trainingenv.verify(sourceManifest,sourceDir);
destination=fullfile(sessionDir,'environment');
assert(~isfolder(destination) && ~isfile(fullfile(sessionDir,'environment.json')), ...
    'Environment:Exists','Refusing to overwrite an environment snapshot.');
staging=fullfile(sessionDir,'environment.preparing');
assert(~isfolder(staging),'Environment:Incomplete','Incomplete environment preparation exists.');
mkdir(staging);
for i=1:numel(manifest.files)
    copyfile(fullfile(sourceDir,manifest.files(i).name),fullfile(staging,manifest.files(i).name));
end
trainingenv.verify(sourceManifest,staging);
trainingenv.verify(sourceManifest,sourceDir);
movefile(staging,destination);
trainingcurriculum.write_json(fullfile(sessionDir,'environment.json'),manifest);
end
