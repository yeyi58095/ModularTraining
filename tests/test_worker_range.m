function test_worker_range()
% Exercise same-attempt range negotiation using fake pool APIs; no workers/train.
root = fileparts(fileparts(mfilename('fullpath')));
output = fullfile(root,'tests','output');
if ~isfolder(output), mkdir(output); end
fixture = tempname(output); mkdir(fixture);
oldPath = path;
guard = onCleanup(@() restore(oldPath)); %#ok<NASGU>
mock = fullfile(fixture,'mock'); mkdir(mock);
writeSource(fullfile(mock,'parcluster.m'), [ ...
    "function c = parcluster(varargin)"
    "c = struct('Profile','test','ClusterMatlabRoot',matlabroot,'JobStorageLocation','test');"
    "end"]);
writeSource(fullfile(mock,'parpool.m'), [ ...
    "function p = parpool(~,range)"
    "global testPoolCalls testPoolRange testPoolAvailable"
    "testPoolCalls = testPoolCalls + 1; testPoolRange = range;"
    "if testPoolAvailable < range(1), error('Test:Unavailable','Insufficient workers'); end"
    "p = struct('NumWorkers',min(testPoolAvailable,range(2)));"
    "end"]);
addpath(fullfile(root,'runtime'),'-begin');
addpath(mock,'-begin');
clear parcluster parpool;
global testPoolCalls testPoolRange testPoolAvailable
testPoolCalls = 0; testPoolAvailable = 3;
diagnostic = fullfile(fixture,'success'); mkdir(diagnostic);
p = checkpoint_open_pool(6,diagnostic,1);
assert(p.NumWorkers == 3 && testPoolCalls == 1);
assert(isequal(testPoolRange,[1 6]));
ready = jsondecode(fileread(fullfile(diagnostic,'pool_ready.json')));
assert(ready.requestedWorkers == 6 && ready.minimumWorkers == 1 && ready.actualWorkers == 3);
% A failed pool cannot be treated as a usable partial pool.
failed = fullfile(fixture,'failed'); mkdir(failed);
rejected = false;
try, checkpoint_open_pool(6,failed,4); catch err, rejected = strcmp(err.identifier,'Test:Unavailable'); end
assert(rejected && ~isfile(fullfile(failed,'pool_ready.json')));
assert(isfile(fullfile(failed,'pool_error.json')));
% Fixed-count mode and the legacy two-argument call are both supported.
testPoolAvailable = 6;
checkpoint_open_pool(6,'',6); assert(isequal(testPoolRange,[6 6]));
checkpoint_open_pool(6,''); assert(isequal(testPoolRange,[1 6]));
before = testPoolCalls;
rejected = false;
try, checkpoint_open_pool(2,'',3); catch, rejected = true; end
assert(rejected && testPoolCalls == before);
fprintf('PASS: same-attempt smaller pool, diagnostic counts, failed pool, bounds and legacy call.\n');
end

function writeSource(file,lines)
fid = fopen(file,'w'); assert(fid~=-1);
guard = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',lines);
end

function restore(oldPath)
path(oldPath);
clear parcluster parpool;
clear global testPoolCalls testPoolRange testPoolAvailable;
end
