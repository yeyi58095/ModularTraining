function pool = checkpoint_open_pool(numWorkers, diagnosticDir, minWorkers)
% Record facts before starting workers, including failures that never return.
    if nargin < 3, minWorkers = 1; end
    validateattributes(numWorkers,{'numeric'},{'scalar','integer','positive','finite'});
    validateattributes(minWorkers,{'numeric'},{'scalar','integer','positive','finite','<=',numWorkers});
    cluster = parcluster('local');
    info = struct('requestedWorkers',numWorkers,'minimumWorkers',minWorkers, ...
        'release',version('-release'), ...
        'matlabRoot',matlabroot,'profile',cluster.Profile, ...
        'clusterMatlabRoot',cluster.ClusterMatlabRoot, ...
        'jobStorageLocation',cluster.JobStorageLocation, ...
        'started',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
    writeJson(diagnosticDir,'pool_starting.json',info);
    started = tic;
    try
        % Accept a successful smaller pool in THIS attempt. A failed pool is
        % not usable and still requires the supervisor's recovery path.
        pool = parpool(cluster,[minWorkers numWorkers]);
    catch err
        info.elapsedSeconds = toc(started);
        info.identifier = err.identifier;
        info.report = getReport(err,'extended','hyperlinks','off');
        writeJson(diagnosticDir,'pool_error.json',info);
        rethrow(err);
    end
    info.actualWorkers = pool.NumWorkers;
    info.elapsedSeconds = toc(started);
    writeJson(diagnosticDir,'pool_ready.json',info);
    fprintf('Pool ready: %d workers (requested up to %d, minimum %d).\n', ...
        pool.NumWorkers,numWorkers,minWorkers);
end

function writeJson(folder,name,value)
    if strlength(string(folder)) == 0, return; end
    path = fullfile(folder,name);
    temp = [path '.tmp'];
    fid = fopen(temp,'w','n','UTF-8');
    assert(fid ~= -1,'Cannot write pool diagnostics.');
    guard = onCleanup(@() fclose(fid));
    fprintf(fid,'%s',jsonencode(value,PrettyPrint=true));
    clear guard;
    movefile(temp,path,'f');
end
