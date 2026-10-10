function filename = resolve_curriculum_path(value)
% Resolve project-relative definitions, including the retired v1 entry path.
root=fileparts(mfilename('fullpath')); filename=char(value);
if ~java.io.File(filename).isAbsolute(), filename=fullfile(root,filename); end
filename=char(java.io.File(filename).getCanonicalPath());
legacy=fullfile(root,'curricula','progressive_v1.json');
if strcmpi(filename,legacy)
    filename=fullfile(root,'experiments','progressive_v1','curriculum.json');
    warning('Curriculum:Moved','Use experiments/progressive_v1/curriculum.json for new experiments.');
end
end
