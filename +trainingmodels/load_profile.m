function spec = load_profile(name)
% Resolve a model's definition without adding its training results to the path.
name = string(name);
assert(isscalar(name) && ~isempty(regexp(name,'^[a-z][a-z0-9_]*$','once')), ...
    'Modular:ModelName','Use a model profile name, not a file path.');
modelDir = fullfile(fileparts(mfilename('fullpath')),name);
assert(isfile(fullfile(modelDir,name+'.m')), ...
    'Modular:UnknownModel','Unknown model profile: %s',name);
oldPath = path; guard = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(modelDir,'-begin');
spec = feval(char(name));
end
