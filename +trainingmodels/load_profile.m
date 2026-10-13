function spec = load_profile(name)
% 模型規格讀取：驗證名稱格式，定位同名模型函式並回傳其 profile 資料。
% 輸入模型名稱，回傳 spec；只將定義目錄加入暫時路徑，不納入 runs 成果。
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
