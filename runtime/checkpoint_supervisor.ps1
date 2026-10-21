# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 訓練 supervisor：鎖住單一 run，循環建立 attempts、啟動全新 MATLAB 並讀取結果。
# 監看 STOP／watchdog、選擇 worker 備援與無進度上限；只清理可驗證屬於自己的程序，保留已保存 checkpoint。
# param 定義此腳本可接受的命名參數；呼叫者用 -ConfigFile／-SessionPath 等名稱傳值。
# [Parameter(Mandatory=$true)] 表示必填；[ValidatePattern(...)] 在執行主體前驗證字串格式。
param([Parameter(Mandatory=$true)][string]$ConfigFile)
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference = 'Stop'
# 行首的「.」是 dot sourcing：在目前作用域載入輔助腳本，讓其中定義的函式可直接呼叫。
# Join-Path 正確拼接目錄與檔名；$PSScriptRoot 是此 .ps1 自己所在的資料夾。
. (Join-Path $PSScriptRoot 'checkpoint_watchdog.ps1')
# 行首的「.」是 dot sourcing：在目前作用域載入輔助腳本，讓其中定義的函式可直接呼叫。
# Join-Path 正確拼接目錄與檔名；$PSScriptRoot 是此 .ps1 自己所在的資料夾。
. (Join-Path $PSScriptRoot 'checkpoint_worker_diagnostics.ps1')
# [Text.UTF8Encoding]::new($false) 呼叫 .NET 建構子；false 表示輸出不加 BOM。
$utf8 = [Text.UTF8Encoding]::new($false)
# Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
$initial = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
# [IO.Path]::GetFullPath 是 .NET 靜態方法，將位置規範成絕對路徑；:: 呼叫型別方法，. 呼叫物件成員。
$sessionDir = [IO.Path]::GetFullPath($initial.sessionDir)
# [IO.Path]::GetFullPath 是 .NET 靜態方法，將位置規範成絕對路徑；:: 呼叫型別方法，. 呼叫物件成員。
$scriptDir = [IO.Path]::GetFullPath($initial.scriptDir)
$matlabExe = [string]$initial.matlabExe
$stopFile = Join-Path $sessionDir 'STOP'
$logFile = Join-Path $sessionDir 'supervisor.log'
$statusFile = Join-Path $sessionDir 'status.json'
# @{} 建立 PID→啟動時間的 hashtable；之後用 $owned[$pid] 存取，避免把重用 PID 當成舊程序。
$owned = @{}
# 先以 $null 初始化資源，finally 用它判斷本次是否真的取得程序／鎖／串流，避免對空值清理。
$child = $null
$attempt = 0
# 先以 $null 初始化資源，finally 用它判斷本次是否真的取得程序／鎖／串流，避免對空值清理。
$lock = $null
$workerIndex = 0
$previousTarget = 0
# -f 是字串格式化運算子；{0:D5} 將 attempt 補零到五位，例如 attempt_00008。
$attemptDir = $null
$diagnosticDir = Join-Path (Join-Path $scriptDir 'training_diagnostics') ([IO.Path]::GetFileName($sessionDir))
if ($null -ne $initial.diagnosticRoot) {
    $diagnosticDir = Join-Path ([string]$initial.diagnosticRoot) ([IO.Path]::GetFileName($sessionDir))
}
if ($null -ne $initial.diagnosticDir) {
    $diagnosticDir = [string]$initial.diagnosticDir
}

# 讀 pool_ready 取得 actualWorkers，將完成 episode 列附加到診斷 CSV。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Update-WorkerDiagnostics {
    $readyPath = Join-Path $attemptDir 'pool_ready.json'
    if (Test-Path -LiteralPath $readyPath) {
        $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
        # $script: 前綴寫入整支腳本作用域；不加前綴的函式內賦值可能只改到函式區域變數。
        $script:actualWorkers = [int]$ready.actualWorkers
        # $script: 前綴寫入整支腳本作用域；不加前綴的函式內賦值可能只改到函式區域變數。
        $script:startupComplete = $true
    }
    Save-EpisodeWorkers -StdoutPath (Join-Path $attemptDir 'stdout.log') `
        -CsvPath (Join-Path $diagnosticDir 'episode_workers.csv') -Attempt $attempt `
        -Target $targetWorkers -Actual $actualWorkers -Seen $seenEpisodes
}

# 複製本次 attempt 的 log／JSON 及 supervisor 狀態到診斷位置。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Archive-Attempt {
    if (-not $attemptDir -or -not (Test-Path -LiteralPath $attemptDir)) { return }
    $archive = Join-Path $diagnosticDir ([IO.Path]::GetFileName($attemptDir))
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null = New-Item -ItemType Directory -Path $archive -Force
    # Get-ChildItem 產生檔案物件；Where-Object 用 $_ 篩選目前檔案，下一個管線命令繼續接收符合條件的物件。
    # -LiteralPath 將路徑視為字面值，避免路徑中的 [ ] 等符號被當成萬用字元。
    Get-ChildItem -LiteralPath $attemptDir -File | Where-Object { $_.Extension -in @('.log','.json') } |
        Copy-Item -Destination $archive -Force
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($name in @('supervisor.log','control.json','status.json')) {
        $path = Join-Path $sessionDir $name
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $diagnosticDir -Force }
    }
}

# 將含時間戳的 supervisor 訊息附加到日誌。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Write-Log([string]$message) {
    [IO.File]::AppendAllText($logFile, ('{0:u} {1}{2}' -f [DateTime]::Now,$message,[Environment]::NewLine), $utf8)
}
# 同步寫 status.json 與日誌，讓外部工具了解目前狀態。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Write-Status([string]$state, [string]$message) {
    # @{key=value; ...} 是 hashtable，保存有名稱的欄位；ConvertTo-Json 再把它寫為 JSON 物件。
    $value = @{state=$state; message=$message; attempt=$attempt; updated=[DateTime]::Now.ToString('o')}
    # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
    [IO.File]::WriteAllText($statusFile, ($value | ConvertTo-Json), $utf8)
    Write-Log "$state : $message"
}
# 只搜尋本 run 的合法 AgentN／Final，依修改時間排序，排除巢狀 runs。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Get-Candidates {
    # Search ONLY this supervisor session; never pick another experiment's agent.
    # Get-ChildItem 產生檔案物件；Where-Object 用 $_ 篩選目前檔案，下一個管線命令繼續接收符合條件的物件。
    # -LiteralPath 將路徑視為字面值，避免路徑中的 [ ] 等符號被當成萬用字元。
    $files = @(Get-ChildItem -LiteralPath $sessionDir -Recurse -File -Filter '*.mat' |
        # Where-Object { ... } 是條件篩選；$_ 代表逐個進來的物件，.Name／.FullName 等取其屬性。
        Where-Object { ($_.Name -eq 'Agent_Final.mat' -or $_.Name -match '^Agent_?\d+\.mat$') -and
            $_.FullName.Substring($sessionDir.Length) -notmatch '[\\/](runs|environment|environment\.preparing)[\\/]' } |
        # Sort-Object 按指定屬性排序；-Descending 由大到小，這裡用修改時間建立優先候選順序。
        Sort-Object LastWriteTimeUtc -Descending)
    # ForEach-Object 把每個檔案物件換成 .FullName 字串；外層 @() 保證零個／一個結果也保留陣列介面。
    $paths = @($files | ForEach-Object { $_.FullName })
    # -not 是邏輯否定；IsNullOrWhiteSpace 同時排除 null、空字串及只含空白的來源設定。
    if (-not [string]::IsNullOrWhiteSpace([string]$initial.resumeAgentFile)) {
        $paths += [string]$initial.resumeAgentFile
    }
    return $paths
}
# 記住 PID 與程序啟動時間，避免之後 PID 重用時誤殺其他程序。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Remember-Process([int]$taskPid) {
    if (-not $owned.ContainsKey($taskPid)) {
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        try {
            $proc = Get-Process -Id $taskPid -ErrorAction Stop
            $owned[$taskPid] = $proc.StartTime.ToUniversalTime().Ticks
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        } catch { }
    }
}
# 追溯且驗證已知父程序，記錄本 supervisor 所屬子程序與診斷快照。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Remember-Descendants {
    # Get-CimInstance 讀 Windows 程序清單，外層 @() 固定為陣列；這是讀取盤點，不是啟動或終止程序。
    $inventory = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    # do/while 至少執行一次；找到新子程序後再掃一輪，直到沒有新增成員。
    do {
        $added = $false
        # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
        foreach ($entry in $inventory) {
            # [int] 將 Windows PID 欄位轉成整數，確保 hashtable 的 key 型別一致。
            $parentKey = [int]$entry.ParentProcessId
            # [int] 將 Windows PID 欄位轉成整數，確保 hashtable 的 key 型別一致。
            $childKey = [int]$entry.ProcessId
            if ($owned.ContainsKey($parentKey) -and -not $owned.ContainsKey($childKey)) {
                # Only attribute new children to a still-verifiable parent.
                # If it has already exited, leave unobserved orphans alone.
                # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
                try {
                    $parentProcess = Get-Process -Id $parentKey -ErrorAction Stop
                    # -eq 是相等、-ne 是不等；比對啟動時間而非只看 PID，確認仍是本 supervisor 記住的程序。
                    if ($parentProcess.StartTime.ToUniversalTime().Ticks -ne $owned[$parentKey]) { continue }
                # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
                } catch { continue }
                if ($entry.CreationDate.ToUniversalTime().Ticks -ge $owned[$parentKey]) {
                    Remember-Process $childKey
                    if ($owned.ContainsKey($childKey)) { $added = $true }
                }
            }
        }
    # do/while 至少執行一次；找到新子程序後再掃一輪，直到沒有新增成員。
    } while ($added)
    if ($attemptDir) {
        $snapshot = @($inventory | Where-Object { $owned.ContainsKey([int]$_.ProcessId) } |
            Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CreationDate)
        if ($snapshot.Count -gt 0) {
            # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
            [IO.File]::WriteAllText((Join-Path $attemptDir 'processes.json'), (ConvertTo-Json -InputObject $snapshot -Depth 4), $utf8)
        }
    }
}
# 只終止 PID／啟動時間仍匹配的所屬程序，全部確認退出才允許新 attempt。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Stop-OwnedProcesses {
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($taskPid in @($owned.Keys)) {
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        try {
            $proc = Get-Process -Id $taskPid -ErrorAction Stop
            # -eq 是相等、-ne 是不等；比對啟動時間而非只看 PID，確認仍是本 supervisor 記住的程序。
            if ($proc.StartTime.ToUniversalTime().Ticks -eq $owned[$taskPid]) {
                # Stop-Process -Id 只針對已驗證所屬 PID；-Force 強制結束，-ErrorAction Stop 讓失敗進入 catch。
                Stop-Process -Id $taskPid -Force -ErrorAction Stop
                # WaitForExit(10000) 的單位是毫秒；只等本次所屬程序。| Out-Null 丟棄無需回傳的等待結果。
                $proc.WaitForExit(10000) | Out-Null
            }
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        } catch { }
    }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($taskPid in @($owned.Keys)) {
        $proc = Get-Process -Id $taskPid -ErrorAction SilentlyContinue
        if ($null -ne $proc -and $proc.StartTime.ToUniversalTime().Ticks -eq $owned[$taskPid]) {
            throw "Owned process $taskPid is still alive; refusing to start a replacement pool."
        }
        $owned.Remove($taskPid)
    }
}
# try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
try {
    # 整個 supervisor 生命週期持有 run 鎖，避免另一份 supervisor 同時續訓。
    # 以 .NET 開啟 supervisor.lock，FileShare.None／'None' 禁止其他工具同時開啟：這就是排他鎖。
    # 鎖是保持開啟的檔案 handle；finally 的 Dispose 關閉它才釋放鎖，並非刪掉 lock 檔。
    $lock = [IO.File]::Open((Join-Path $sessionDir 'supervisor.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null = New-Item -ItemType Directory -Path $diagnosticDir -Force
    if (-not (Test-Path -LiteralPath $matlabExe -PathType Leaf)) { throw 'Configured MATLAB executable not found.' }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($directory in @(Get-ChildItem -LiteralPath $sessionDir -Directory)) {
        # -match 使用正規表示式；(d+) 擷取 attempt 號，PowerShell 自動放到 $Matches[1]，取最大值避免覆寫。
        if ($directory.Name -match '^attempt_(\d+)$') { $attempt = [Math]::Max($attempt,[int]$Matches[1]) }
    }
    $launched = 0
    # 正常結果或新 checkpoint 會清掉失敗連續計數；沒有新保存進度才累積，供上限判斷。
    $noProgressFailures = 0
    # 每次 attempt 前重讀 control，檢查 STOP、參數與本次啟動次數上限。
    # $true 使迴圈持續執行；break 結束迴圈，return 結束整個目前函式／腳本的執行。
    while ($true) {
        # Test-Path 只檢查檔案是否存在；此處用 STOP 檔作為明確停止訊號，不從畫圖工具猜測。
        if (Test-Path -LiteralPath $stopFile) { Write-Status 'stopped' 'STOP requested.'; break }
        # Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
        $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
        # Defaults also support control.json written by older launchers.
        $startupTimeout = 600
        $stallTimeout = 1800
        $licenseDelay = 60
        if ($null -ne $cfg.startupTimeoutSeconds) { $startupTimeout = [double]$cfg.startupTimeoutSeconds }
        if ($null -ne $cfg.stallTimeoutSeconds) { $stallTimeout = [double]$cfg.stallTimeoutSeconds }
        if ($null -ne $cfg.licenseRetryDelaySeconds) { $licenseDelay = [double]$cfg.licenseRetryDelaySeconds }
        # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
        foreach ($timeout in @($startupTimeout,$stallTimeout,$licenseDelay)) {
            if ([double]::IsNaN($timeout) -or [double]::IsInfinity($timeout) -or $timeout -lt 0) { throw 'Watchdog timeouts must be finite, nonnegative seconds.' }
        }
        # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
        foreach ($key in @('numWorkers','checkpointEvery','episodesPerProcess','averageWindow')) {
            if ([double]$cfg.$key -lt 1 -or [double]$cfg.$key -ne [int]$cfg.$key) { throw "Invalid positive integer: $key" }
        }
        $targetWorkers = [int]$cfg.numWorkers
        $minimumWorkers = 1
        if ($null -ne $cfg.minWorkers) {
            $minimum = [double]$cfg.minWorkers
            if ([double]::IsNaN($minimum) -or [double]::IsInfinity($minimum) -or
                $minimum -lt 1 -or $minimum -gt $targetWorkers -or $minimum -ne [Math]::Floor($minimum)) {
                throw 'minWorkers must be an integer between 1 and numWorkers.'
            }
            $minimumWorkers = [int]$minimum
        }
        $fallback = @(4,2)
        if ($null -ne $cfg.fallbackWorkers) { $fallback = @($cfg.fallbackWorkers) }
        # minWorkers 過濾備援上限；當前 attempt 接受 [minimum,requested] 的成功 pool。
        # 管線先取得候選上限，再用 $_ -ge $minimumWorkers 篩掉低於下限者；@() 保存整個計畫陣列。
        $workerPlan = @(Get-WorkerPlan $targetWorkers $fallback | Where-Object { $_ -ge $minimumWorkers })
        if ($previousTarget -ne $targetWorkers -or $workerIndex -ge $workerPlan.Count) { $workerIndex = 0 }
        $previousTarget = $targetWorkers
        $requestedWorkers = $workerPlan[$workerIndex]
        if ($cfg.episodesPerProcess -lt $cfg.averageWindow -or $cfg.episodesPerProcess -lt $cfg.checkpointEvery) {
            throw 'episodesPerProcess must cover both the averaging window and checkpoint interval.'
        }
        if ($cfg.maxAttempts -gt 0 -and $launched -ge $cfg.maxAttempts) {
            Write-Status 'paused' 'Configured maximum attempts reached; checkpoints retained.'; break
        }
        # ++ 將計數器加 1；attempt 是 run 的歷史編號，launched 是本次 supervisor 新啟動次數。
        $attempt++
        # ++ 將計數器加 1；attempt 是 run 的歷史編號，launched 是本次 supervisor 新啟動次數。
        $launched++
        # 每次使用唯一 attempt_目錄，不覆寫過去 stdout／result／設定。
        # -f 是字串格式化運算子；{0:D5} 將 attempt 補零到五位，例如 attempt_00008。
        $attemptDir = Join-Path $sessionDir ('attempt_{0:D5}' -f $attempt)
        if (Test-Path -LiteralPath $attemptDir) { throw 'Attempt directory already exists; start a new session to avoid overwriting.' }
        New-Item -ItemType Directory -Path $attemptDir | Out-Null
        $candidates = @(Get-Candidates)
        # PowerShell 可把 if 分支的輸出指派給變數；Count>0 時取 [0] 第一項，否則使用空字串。
        $beforeNewest = if ($candidates.Count) { $candidates[0] } else { '' }
        # @{key=value; ...} 是 hashtable，保存有名稱的欄位；ConvertTo-Json 再把它寫為 JSON 物件。
        $payload = @{attempt=$attempt; attemptDir=$attemptDir; scriptDir=$scriptDir; sessionDir=$sessionDir;
            resumeCandidates=$candidates; numWorkers=$requestedWorkers; minWorkers=$minimumWorkers; targetWorkers=$targetWorkers; checkpointEvery=$cfg.checkpointEvery;
            episodesPerProcess=$cfg.episodesPerProcess; targetReward=$cfg.targetReward;
            averageWindow=$cfg.averageWindow; trainingDevice=$cfg.trainingDevice}
        if ($null -ne $cfg.modularRoot) {
            $payload.modularRoot = [string]$cfg.modularRoot
        }
        if ($null -ne $cfg.curriculumEnabled) { $payload.curriculumEnabled = [bool]$cfg.curriculumEnabled }
        $attemptConfig = Join-Path $attemptDir 'attempt.json'
        if ($cfg.executionMode) { $payload.executionMode = [string]$cfg.executionMode }
        if ($cfg.fastRestart) { $payload.fastRestart = [string]$cfg.fastRestart }
        # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
        [IO.File]::WriteAllText($attemptConfig, ($payload | ConvertTo-Json -Depth 5), $utf8)
        # 雙引號字串會展開 $變數；$() 先計算其中運算。Replace 將路徑單引號加倍，供 MATLAB 字串安全引用。
        $expression = "addpath('$($scriptDir.Replace("'","''"))'); checkpoint_attempt('$($attemptConfig.Replace("'","''"))');"
        # 單引號字串保留字面內容；+ 串接出 MATLAB 的 -batch 引數，外層雙引號包含整段命令。
        $arguments = '-batch "' + $expression + '"'
        Write-Status 'running' "Starting attempt $attempt with $minimumWorkers..$requestedWorkers workers (target=$targetWorkers); resume=$beforeNewest"
        # 新 MATLAB -batch 隔離 native crash；stdout／stderr 重導向本 attempt。
        # Start-Process 啟動新程序；-PassThru 回傳 Process 物件給 $child，-WindowStyle Hidden 隱藏視窗。
        # -RedirectStandardOutput／Error 將兩種輸出保存到 attempt 日誌；行末反引號是續行符，後面不能再加空白。
        $child = Start-Process -FilePath $matlabExe -ArgumentList $arguments -WorkingDirectory $scriptDir `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $attemptDir 'stdout.log') `
            -RedirectStandardError (Join-Path $attemptDir 'stderr.log')
        # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
        $null = $child.Handle # Retain the handle so ExitCode remains readable.
        Remember-Process $child.Id
        $startedUtc = [DateTime]::UtcNow
        $lastActivityUtc = $startedUtc
        $logSignature = ''
        $startupComplete = $false
        $actualWorkers = 0
        $seenEpisodes = [Collections.Generic.HashSet[int]]::new()
        $restartReason = ''
        # 監控自己所屬程序、STOP 與日誌活動，watchdog 理由決定失敗恢復。
        # HasExited 是 Process 屬性；程序仍活著才繼續監測，Refresh 重新取得程序目前狀態。
        while (-not $child.HasExited) {
            Remember-Descendants
            Update-WorkerDiagnostics
            # Test-Path 只檢查檔案是否存在；此處用 STOP 檔作為明確停止訊號，不從畫圖工具猜測。
            if (Test-Path -LiteralPath $stopFile) {
                Stop-OwnedProcesses
                Write-Status 'stopped' 'Active attempt terminated by STOP; completed checkpoints retained.'
                return
            }
            $tails = @()
            $signatures = @()
            # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
            foreach ($name in @('stdout.log','stderr.log')) {
                $path = Join-Path $attemptDir $name
                if (Test-Path -LiteralPath $path) {
                    $info = Get-Item -LiteralPath $path
                    $signatures += "$name/$($info.Length)/$($info.LastWriteTimeUtc.Ticks)"
                    $tails += @(Get-Content -LiteralPath $path -Tail 80 -ErrorAction SilentlyContinue)
                }
            }
            # -join 把陣列串成一段字串；日誌尾端供 watchdog 判斷，檔案長度／修改時間簽章用於活動檢查。
            $signature = $signatures -join ';'
            if ($signature -ne $logSignature) { $lastActivityUtc = [DateTime]::UtcNow; $logSignature = $signature }
            # -join 把陣列串成一段字串；日誌尾端供 watchdog 判斷，檔案長度／修改時間簽章用於活動檢查。
            $logTail = $tails -join "`n"
            if ($logTail -match '(?im)(Connected to parallel pool with\s+\d+\s+workers|Serial training ready|^\s*Episode:\s*\d+\s*/)') {
                $startupComplete = $true
            }
            $nowUtc = [DateTime]::UtcNow
            # -參數名 值 是 PowerShell 的命名參數傳法；函式只返回原因，呼叫端才決定終止／重啟。
            $restartReason = Get-CheckpointWatchdogReason -LogTail $logTail -StartupComplete $startupComplete `
                -ElapsedSeconds ($nowUtc-$startedUtc).TotalSeconds -IdleSeconds ($nowUtc-$lastActivityUtc).TotalSeconds `
                -StartupTimeoutSeconds $startupTimeout -StallTimeoutSeconds $stallTimeout
            if ($restartReason) {
                Write-Status 'restarting' "Watchdog: $restartReason. Terminating this attempt before checkpoint recovery."
                Stop-OwnedProcesses
                # WaitForExit(10000) 的單位是毫秒；只等本次所屬程序。| Out-Null 丟棄無需回傳的等待結果。
                if (-not $child.WaitForExit(10000)) { throw 'Could not terminate stalled MATLAB; refusing to launch another copy.' }
                break
            }
            Start-Sleep -Seconds 5
            $child.Refresh()
        }
        $child.WaitForExit()
        $exitCode = $child.ExitCode
        Update-WorkerDiagnostics
        if (-not $restartReason) {
            # Fast startup failures may exit between polls; still apply license cooldown.
            $endedTail = @()
            # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
            foreach ($name in @('stdout.log','stderr.log')) {
                $endedTail += @(Get-Content -LiteralPath (Join-Path $attemptDir $name) -Tail 80 -ErrorAction SilentlyContinue)
            }
            # -參數名 值 是 PowerShell 的命名參數傳法；函式只返回原因，呼叫端才決定終止／重啟。
            $restartReason = Get-CheckpointWatchdogReason -LogTail ($endedTail -join "`n") `
                -StartupComplete $true -ElapsedSeconds 0 -IdleSeconds 0 -StartupTimeoutSeconds 0 -StallTimeoutSeconds 0
        }
        # Native crashes may leave workers alive. Touch only verified descendants.
        Remember-Descendants
        Stop-OwnedProcesses
        $startingPath = Join-Path $attemptDir 'pool_starting.json'
        # -and 要兩個條件都成立；pool_starting 存在但未就緒才視為建池啟動失敗。
        $startupFailed = (-not $startupComplete -and (Test-Path -LiteralPath $startingPath))
        $reason = $restartReason
        if (-not $reason) {
            if ($startupFailed) { $reason = 'pool_start_failed' }
            elseif ($exitCode -eq 0) { $reason = 'normal_exit' }
            else { $reason = 'matlab_error' }
        }
        # [pscustomobject] 將欄位表轉為資料物件，Export-Csv 可按欄位輸出一列；-Append 保留既有列。
        [pscustomobject]@{Attempt=$attempt; TargetWorkers=$targetWorkers; RequestedWorkers=$requestedWorkers;
            ActualWorkers=$actualWorkers; PoolReady=$startupComplete; Reason=$reason; ExitCode=$exitCode;
            Started=$startedUtc.ToString('o'); Ended=[DateTime]::UtcNow.ToString('o');
            DurationSeconds=[Math]::Round(([DateTime]::UtcNow-$startedUtc).TotalSeconds,1)} |
            Export-Csv -LiteralPath (Join-Path $diagnosticDir 'worker_attempts.csv') -Append -NoTypeInformation -Encoding UTF8
        Archive-Attempt
        # 只在符合啟動失敗條件時使用較低備援；正常下一段回到要求上限。
        $nextIndex = Get-NextWorkerIndex $workerIndex $workerPlan.Count $startupComplete $startupFailed
        # -gt 表示大於；索引增加才代表改用較小備援，不是每次正常段落都降級。
        $hasFallback = $nextIndex -gt $workerIndex
        $workerIndex = $nextIndex
        $resultFile = Join-Path $attemptDir 'result.json'
        $result = $null
        if (Test-Path -LiteralPath $resultFile) { $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json }
        # pause 優先終止迴圈，保留 checkpoint；不解除 guard、回滾或自動新建分支。
        # -eq 0 表示 MATLAB 正常退出；仍需 result 非空且指定旗標成立，不能只憑程序退出宣告 pause／success。
        if ($exitCode -eq 0 -and $null -ne $result -and $result.pause) {
            if ($result.pauseReason) {
                Write-Status 'paused' "Training guard: $($result.pauseReason); saved progress retained, no automatic rollback."
            } else {
                Write-Status 'paused' "Curriculum stage $($result.stageId) reached its episode budget without passing; saved progress retained."
            }
            break
        }
        # 確認成功檔存在再發布 success.json，避免僅憑 stdout 宣告完成。
        # -eq 0 表示 MATLAB 正常退出；仍需 result 非空且指定旗標成立，不能只憑程序退出宣告 pause／success。
        if ($exitCode -eq 0 -and $null -ne $result -and $result.success) {
            if (-not (Test-Path -LiteralPath $result.successAgent -PathType Leaf)) {
                throw 'Attempt reported success but Agent_Success.mat is missing.'
            }
            # Publish a convenient session-level copy only after the copy completes.
            $successAgent = Join-Path $sessionDir 'Agent_Success.mat'
            $successTemporary = Join-Path $sessionDir 'Agent_Success.pending.mat'
            if ([IO.Path]::GetFullPath($result.successAgent) -ne [IO.Path]::GetFullPath($successAgent)) {
                Copy-Item -LiteralPath $result.successAgent -Destination $successTemporary -ErrorAction Stop
                # 這一步發布已驗證的暫存副本／檔案；驗證前不把半成品當正式結果。
                Move-Item -LiteralPath $successTemporary -Destination $successAgent -ErrorAction Stop
            }
            # @{key=value; ...} 是 hashtable，保存有名稱的欄位；ConvertTo-Json 再把它寫為 JSON 物件。
            $provenance = @{attempt=$attempt; averageReward=$result.averageReward;
                sourceAgent=$result.successAgent; successAgent=$successAgent; completed=[DateTime]::Now.ToString('o')}
            # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
            [IO.File]::WriteAllText((Join-Path $sessionDir 'success.json'), ($provenance | ConvertTo-Json), $utf8)
            if ($result.curriculumDecision -eq 'complete') {
                Write-Status 'success' "Curriculum completed: reason=$($result.curriculumReason); agent=$successAgent"
            } else {
                Write-Status 'success' "Target met: average reward=$($result.averageReward); agent=$successAgent"
            }
            break
        }
        $afterCandidates = @(Get-Candidates)
        # PowerShell 可把 if 分支的輸出指派給變數；Count>0 時取 [0] 第一項，否則使用空字串。
        $afterNewest = if ($afterCandidates.Count) { $afterCandidates[0] } else { '' }
        if (($exitCode -eq 0 -and $null -ne $result) -or $afterNewest -ne $beforeNewest) {
            # 正常結果或新 checkpoint 會清掉失敗連續計數；沒有新保存進度才累積，供上限判斷。
            $noProgressFailures = 0
        # 正常結果或新 checkpoint 會清掉失敗連續計數；沒有新保存進度才累積，供上限判斷。
        } else { $noProgressFailures++ }
        # 備援用盡且連續沒有新進度才按上限暫停，避免永無止境重試。
        if (-not $hasFallback -and $cfg.maxNoProgressFailures -gt 0 -and $noProgressFailures -ge $cfg.maxNoProgressFailures) {
            Write-Status 'paused' "Failed $noProgressFailures times without a new checkpoint. Inspect latest stdout/stderr; refusing an endless identical failure loop."
            break
        }
        Write-Status 'retrying' "Attempt exited ($exitCode); reason=$reason; next workers=$($workerPlan[$workerIndex]) (target=$targetWorkers). Restarting from newest readable checkpoint; no-progress failures=$noProgressFailures."
        $delay = [int]$cfg.retryDelaySeconds
        if ($restartReason -eq 'license_error') { $delay = [Math]::Max($delay,[int]$licenseDelay) }
        # for(初始值;條件;每輪變化) 倒數等待；每秒再看 STOP，所以等待期間仍可響應停止。
        for ($remaining = $delay; $remaining -gt 0; $remaining--) {
            # Test-Path 只檢查檔案是否存在；此處用 STOP 檔作為明確停止訊號，不從畫圖工具猜測。
            if (Test-Path -LiteralPath $stopFile) { break }
            Start-Sleep -Seconds 1
        }
    }
# try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
} catch {
    Write-Status 'error' $_.Exception.Message
    throw
# 正常停止與錯誤都清理所屬程序、封存診斷並釋放鎖。
# finally 無論成功、return 或例外都執行；Dispose 釋放本次鎖／串流，不代表刪除訓練成果。
} finally {
    Stop-OwnedProcesses
    if ($null -ne $lock -and $attemptDir) {
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        try { Update-WorkerDiagnostics; Archive-Attempt } catch { Write-Warning "Diagnostic archive: $_" }
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
