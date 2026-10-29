function plan = load_plan(filename, checkFiles)
% 課程 schema 驗證：檢查模型、階段、軌跡、整數風場及 all／any 過關條件。
% 輸入 JSON 檔與 checkFiles；回傳規範化 plan。checkFiles=true 才讀 MAT，從不執行 JSON 內的程式。
% Read a declarative curriculum. No expressions or scripts are evaluated.
if nargin < 2, checkFiles = true; end
plan = jsondecode(fileread(filename));
% allowed／required 並用會拒絕未知欄位與缺漏；JSON 本身不支援 // 註解或任意新增說明鍵。
keys(plan,{'schema_version','model','environment','stages'}, {'schema_version','model','stages'});
must(isequal(plan.schema_version,1) || isequal(plan.schema_version,2),'schema_version must be 1 or 2.');
if isequal(plan.schema_version,2)
    must(isfield(plan,'environment') && ischar(plan.environment) && ...
        ~isempty(regexp(plan.environment,'^[a-z][a-z0-9_]*$','once')),'Version 2 requires environment id.');
else
    must(~isfield(plan,'environment'),'environment requires schema_version 2.');
end
must(ischar(plan.model) && ~isempty(regexp(plan.model,'^[a-z][a-z0-9_]*$','once')), 'Invalid model name.');
plan.stages = asCells(plan.stages);
must(~isempty(plan.stages),'At least one stage is required.');
ids = strings(0);
for i=1:numel(plan.stages)
    s=plan.stages{i};
    keys(s,{'id','trajectory','wind','advance_when','max_episodes','on_limit','frozen_gate'}, ...
        {'id','trajectory','wind','advance_when','max_episodes','on_limit'});
    must(ischar(s.id) && ~isempty(regexp(s.id,'^[a-z][a-z0-9_]*$','once')),'Invalid stage id.');
    must(~any(ids==string(s.id)),'Stage ids must be unique.'); ids(end+1)=string(s.id); %#ok<AGROW>
    positiveInteger(s.max_episodes,'max_episodes');
    must(any(strcmp(s.on_limit,{'pause','advance','continue'})),'on_limit must be pause, advance or continue.');
    t=s.trajectory;
    must(isstruct(t) && isscalar(t) && isfield(t,'type'),'trajectory.type is required.');
    % 固定內建、random、MAT 的允許欄位各自不同，不能把 retry 硬體參數混入 trajectory。
    switch t.type
        case 'fixed_builtin'
            keys(t,{'type'},{'type'});
        case 'random'
            keys(t,{'type','refresh_every_worker_episodes','seed_range'},{'type','refresh_every_worker_episodes'});
            positiveInteger(t.refresh_every_worker_episodes,'refresh_every_worker_episodes');
            if isfield(t,'seed_range')
                v=t.seed_range;
                must(isnumeric(v) && numel(v)==2 && all(isfinite(v)) && all(fix(v)==v) && ...
                    v(1)>=0 && v(1)<=v(2) && v(2)<=2^32-1,'Invalid route seed range.');
            end
        case 'mat'
            keys(t,{'type','file','waypoints_variable','velocity_variable'}, ...
                {'type','file','waypoints_variable','velocity_variable'});
            must(ischar(t.file) && ~isempty(t.file) && isempty(regexp(t.file,'^([A-Za-z]:|[/\\])','once')), ...
                'MAT paths must be relative to the JSON file.');
            [~,~,ext]=fileparts(t.file); must(strcmpi(ext,'.mat'),'Trajectory file must end in .mat.');
            for key={'waypoints_variable','velocity_variable'}
                must(ischar(t.(key{1})) && isvarname(t.(key{1})),'Invalid MAT variable name.');
            end
            if checkFiles
                trainingcurriculum.load_trajectory(t,fileparts(filename));
            end
        otherwise
            error('Curriculum:Invalid','Unknown trajectory type.');
    end
    keys(s.wind,{'east_mps','north_mps','turbulence'}, {'east_mps','north_mps','turbulence'});
    for key={'east_mps','north_mps','turbulence'}
        range=s.wind.(key{1});
        must(isnumeric(range) && numel(range)==2 && all(isfinite(range(:))) && ...
            all(fix(range(:))==range(:)) && range(1)<=range(2),'Wind ranges must be ordered integer pairs.');
    end
    must(all(s.wind.turbulence>=0 & s.wind.turbulence<=2),'Turbulence levels must be within 0..2.');
    validateCondition(s.advance_when,0);
    if isfield(s,'frozen_gate')
        g=s.frozen_gate;
        keys(g,{'seeds','max_distance_m','max_rms_m'},{'seeds','max_distance_m','max_rms_m'});
        must(isnumeric(g.seeds) && ~isempty(g.seeds) && numel(unique(g.seeds))==numel(g.seeds) && ...
            all(isfinite(g.seeds)) && all(fix(g.seeds)==g.seeds) && all(g.seeds>=0 & g.seeds<=2^32-1),'Invalid gate seeds.');
        for key={'max_distance_m','max_rms_m'}
            v=g.(key{1});must(isnumeric(v) && isscalar(v) && isfinite(v) && v>0,'Invalid gate distance.');
        end
        must(strcmp(t.type,'random') && isfield(t,'seed_range'),'Gate requires seeded random routes.');
        must(all(g.seeds<t.seed_range(1) | g.seeds>t.seed_range(2)),'Gate seeds overlap training seeds.');
    end
end
end

function validateCondition(c,depth)
% 遞迴檢查 all／any 或葉條件；限制深度，驗證視窗、比例與門檻欄位。
must(depth<=8,'Conditions are nested too deeply.');
must(isstruct(c) && isscalar(c),'Condition must be an object.');
if isfield(c,'all') || isfield(c,'any')
    must(xor(isfield(c,'all'),isfield(c,'any')),'Use either all or any.');
    if isfield(c,'all'), key='all'; else, key='any'; end
    keys(c,{key},{key}); children=asCells(c.(key));
    must(~isempty(children),'all/any must contain conditions.');
    for i=1:numel(children), validateCondition(children{i},depth+1); end
    return;
end
keys(c,{'metric','at_least','at_most','window','consecutive_windows','steps_at_least'},{'metric'});
must(xor(isfield(c,'at_least'),isfield(c,'at_most')),'Use exactly one of at_least or at_most.');
if isfield(c,'at_least'), threshold=c.at_least; else, threshold=c.at_most; end
must(isnumeric(threshold) && isscalar(threshold) && isfinite(threshold),'Threshold must be finite.');
switch c.metric
    case 'stage_episodes'
        must(~any(isfield(c,{'window','consecutive_windows','steps_at_least'})), 'stage_episodes has no window.');
        must(threshold>=1 && fix(threshold)==threshold,'Episode threshold must be a positive integer.');
    case {'reward_mean','steps_mean','full_length_rate'}
        must(isfield(c,'window'),'Window is required.'); positiveInteger(c.window,'window');
        if isfield(c,'consecutive_windows'), positiveInteger(c.consecutive_windows,'consecutive_windows'); end
        if strcmp(c.metric,'full_length_rate')
            must(threshold>=0 && threshold<=1,'Rate threshold must be within 0..1.');
            must(isfield(c,'steps_at_least'),'full_length_rate requires steps_at_least.');
            positiveInteger(c.steps_at_least,'steps_at_least');
        else
            must(~isfield(c,'steps_at_least'),'steps_at_least only applies to full_length_rate.');
        end
    otherwise
        error('Curriculum:Invalid','Unknown metric: %s',string(c.metric));
end
end

function keys(value,allowed,required)
% 拒絕未知欄位與缺少必要欄位，讓 JSON 拼字錯誤在訓練前被發現。
must(isstruct(value) && isscalar(value),'Expected an object.');
must(all(ismember(fieldnames(value),allowed)),'Unknown setting (possible typo).');
must(all(isfield(value,required)),'Missing required setting.');
end
function result=asCells(value)
% 兼容 jsondecode 的 struct array／cell 表示，統一為 cell 方便逐項處理。
if iscell(value), result=value;
elseif isstruct(value), result=num2cell(value);
else, error('Curriculum:Invalid','Expected an array of objects.'); end
end
function positiveInteger(v,name)
% 要求有限、正整數，將錯誤名稱帶入 schema 訊息。
must(isnumeric(v) && isscalar(v) && isfinite(v) && v>=1 && fix(v)==v,[name ' must be a positive integer.']);
end
function must(condition,message)
% 統一拋出 Curriculum:Invalid，保留具體設定錯誤說明。
assert(condition,'Curriculum:Invalid','%s',message);
end
