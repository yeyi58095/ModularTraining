function rows = log_history(sessionDir,seen,upper)
% Read complete stdout rows across recovery ancestry, clipped at fork episodes.
% Missing/ambiguous parents fail closed; no checkpoint or state writes.
if nargin<2, seen={}; end
if nargin<3, upper=Inf; end
sessionDir=char(java.io.File(char(sessionDir)).getCanonicalPath());
assert(~any(strcmpi(seen,sessionDir)),'Curriculum:History','Cycle in recovery ancestry.');
seen{end+1}=sessionDir;
lower=0; parentRows=zeros(0,3);
recoveryFile=fullfile(sessionDir,'recovery.json');
if isfile(recoveryFile)
    recovery=jsondecode(fileread(recoveryFile)); lower=recovery.parent_episode;
    validateattributes(lower,{'numeric'},{'scalar','integer','nonnegative','<=',upper});
    parent=char(recovery.parent_session);
    if ~java.io.File(parent).isAbsolute(), parent=fullfile(sessionDir,parent); end
    if ~isfolder(parent)
        [~,name]=fileparts(char(recovery.parent_session));
        parent=fullfile(fileparts(sessionDir),name);
    end
    if isfolder(parent)
        parentRows=trainingcurriculum.log_history(parent,seen,lower);
    else
        warning('Curriculum:History','Parent logs unavailable: %s; missing episodes remain unknown.',parent);
    end
end
folders=dir(fullfile(sessionDir,'attempt_*')); rows=zeros(0,4);
number='[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?';
pattern=['Episode:\s*(\d+)\s*/\s*\d+\s*\|\s*Episode reward:\s*(' number ...
    ')\s*\|\s*Episode steps:\s*(\d+)\s*\|\s*Average reward:\s*' number ...
    '\s*\|\s*Step Count:\s*\d+\s*\|\s*Episode Q0:\s*' number];
for i=1:numel(folders)
    token=regexp(folders(i).name,'^attempt_(\d+)$','tokens','once');
    logFile=fullfile(sessionDir,folders(i).name,'stdout.log');
    if isempty(token) || ~folders(i).isdir || ~isfile(logFile), continue; end
    lines=regexp(fileread(logFile),'\n','split');
    for j=1:numel(lines)-1 % ignore incomplete final row
        values=regexp(lines{j},pattern,'tokens','once');
        if isempty(values), continue; end
        ep=str2double(values{1});
        if ep<=lower || ep>upper, continue; end
        rows(end+1,:)=[ep,str2double(values{2}),str2double(values{3}),str2double(token{1})]; %#ok<AGROW>
    end
end
if ~isempty(rows)
    rows=sortrows(rows,[1 4]); rows=rows([rows(1:end-1,1)~=rows(2:end,1); true],1:3);
else
    rows=zeros(0,3);
end
rows=[parentRows;rows];
end
