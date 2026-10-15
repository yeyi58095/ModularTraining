function [manifestFile,folder]=registry(root,id)
assert(ischar(id) || (isstring(id) && isscalar(id)),'Environment:Id','Expected an environment id.');
id=char(id);
assert(~isempty(regexp(id,'^[a-z][a-z0-9_]*$','once')),'Environment:Id','Invalid environment id.');
folder=fullfile(root,'environments',id);manifestFile=fullfile(folder,'environment.json');
assert(isfile(manifestFile),'Environment:Unknown','Unknown environment: %s',id);
manifest=trainingenv.verify(manifestFile,folder);
assert(strcmp(manifest.id,id),'Environment:Id','Registry folder/id mismatch.');
end
