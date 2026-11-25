function [dataRoot, outputDir] = diagnostic_paths(task)
% Locate the local bundles and create a separate directory for derived results.
packageDir = fileparts(fileparts(mfilename('fullpath')));
projectRoot = fileparts(fileparts(packageDir));
dataRoot = fullfile(projectRoot,'diagnostic_packages');
if nargout < 2
    return
end
outputParent = fullfile(projectRoot,'artifacts','historical-diagnostics',task);
if ~isfolder(outputParent)
    [ok,message] = mkdir(outputParent);
    assert(ok,'%s',message);
end
outputDir = tempname(outputParent);
[ok,message] = mkdir(outputDir);
assert(ok,'%s',message);
fprintf('Analysis output: %s\n',outputDir);
end
