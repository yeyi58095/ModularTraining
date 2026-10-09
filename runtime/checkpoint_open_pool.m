function pool = checkpoint_open_pool(numWorkers, diagnosticDir)
% Record facts before starting workers, including failures that never return.
    cluster = parcluster('local');
    info = struct('requestedWorkers',numWorkers,'release',version('-release'), ...
        'matlabRoot',matlabroot,'profile',cluster.Profile, ...
        'clusterMatlabRoot',cluster.ClusterMatlabRoot, ...
        'jobStorageLocation',cluster.JobStorageLocation, ...
        'started',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
    writeJson(diagnosticDir,'pool_starting.json',info);
    started = tic;
    try
        pool = parpool(cluster,numWorkers);
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
