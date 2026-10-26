function version=checkpoint_storage_version(sessionDir)
% Opt-in per-run storage policy. Legacy runs retain v7.3.
version='-v7.3';
file=fullfile(sessionDir,'checkpoint_storage.json');
if ~isfile(file),return;end
policy=jsondecode(fileread(file));
assert(policy.schema_version==1 && any(strcmp(policy.version,{'-v7','-v7.3'})), ...
    'Checkpoint:StoragePolicy','Invalid checkpoint storage policy.');
version=char(policy.version);
end
