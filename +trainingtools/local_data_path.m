function resolved = local_data_path(root,value)
% Resolve relative data paths from the checkout, then check the actual volume.
file=java.io.File(char(value));
if ~file.isAbsolute(), file=java.io.File(fullfile(root,char(value))); end
file=file.getCanonicalFile();
rootFile=java.io.File(char(root)).getCanonicalFile();
targetVolume=file.toPath().getRoot();
projectVolume=rootFile.toPath().getRoot();
assert(strcmpi(char(targetVolume.toString()),char(projectVolume.toString())), ...
    'Workspace:ForeignVolume','Data path must be on the same volume as this checkout: %s', ...
    char(file.getPath()));
resolved=char(file.getPath());
end
