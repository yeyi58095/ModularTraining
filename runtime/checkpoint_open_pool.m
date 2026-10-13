function pool = checkpoint_open_pool(numWorkers, diagnosticDir, minWorkers)
% worker 建池：以 [minWorkers,numWorkers] 範圍要求 local pool，保存啟動／成功／失敗診斷。
% 回傳實際可用的整個 pool；成功縮減在同一 attempt 生效，整體失敗拋出例外交 supervisor 恢復。
% Record facts before starting workers, including failures that never return.
    if nargin < 3, minWorkers = 1; end
    validateattributes(numWorkers,{'numeric'},{'scalar','integer','positive','finite'});
    validateattributes(minWorkers,{'numeric'},{'scalar','integer','positive','finite','<=',numWorkers});
    % local cluster 對應本機 process workers；[minimum maximum] 允許 MATLAB 在同次建池協商實際數量。
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
    % catch 保留原始例外；先保存耗時與堆疊再 rethrow，讓 supervisor 看見真正建池錯誤。
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
% 以 UTF-8 保存 JSON；輸入為檔名／資料，呼叫端決定寫入位置與時機。
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
