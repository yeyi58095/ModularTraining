function filename = resolve_curriculum_path(value)
% 課程路徑解析：以本專案根目錄定位相對路徑，並相容舊 progressive_v1 入口。
% 回傳 canonical 絕對路徑；只解析位置，不修改課程內容。
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
