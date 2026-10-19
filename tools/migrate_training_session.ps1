# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 停止實驗遷移：完整複製到新課程目錄，逐檔 SHA256 驗證後才發布目的副本。
# 輸入來源與課程名稱；保留原件，只修正新副本控制路徑，完成後仍需 MATLAB 驗證才可由使用者續訓。
# param 定義此腳本可接受的命名參數；呼叫者用 -ConfigFile／-SessionPath 等名稱傳值。
# [Parameter(Mandatory=$true)] 表示必填；[ValidatePattern(...)] 在執行主體前驗證字串格式。
param(
    [Parameter(Mandatory=$true)][string]$SourceSession,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string]$CurriculumName
)
# Copy, verify, then publish. Never delete or rewrite the original experiment.
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference = 'Stop'
# [IO.Path]::GetFullPath 是 .NET 靜態方法，將位置規範成絕對路徑；:: 呼叫型別方法，. 呼叫物件成員。
$root = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
# Resolve-Path 先確認來源存在；括號取得命令回傳物件，再用 .Path 取路徑字串與 TrimEnd 去尾端分隔符。
$source = (Resolve-Path -LiteralPath $SourceSession).Path.TrimEnd('\','/')
$targetParent = Join-Path (Join-Path (Join-Path $root 'experiments') $CurriculumName) 'runs'
$target = [IO.Path]::GetFullPath((Join-Path $targetParent ([IO.Path]::GetFileName($source))))
if (-not $target.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination outside project.' }
if ($target.StartsWith($source + '\',[StringComparison]::OrdinalIgnoreCase) -or $target -eq $source) { throw 'Destination must not be inside source.' }
if (Test-Path -LiteralPath $target) { throw "Destination already exists; refusing overwrite: $target" }
# 先以 $null 初始化資源，finally 用它判斷本次是否真的取得程序／鎖／串流，避免對空值清理。
$lock = $null
# [Text.UTF8Encoding]::new($false) 呼叫 .NET 建構子；false 表示輸出不加 BOM。
$utf8 = [Text.UTF8Encoding]::new($false)
# 以 UTF-8 保存遷移副本 metadata，呼叫端提供目的路徑。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Write-Json($path,$value) { [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 50),$utf8) }
# try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
try {
    # 先取得排他鎖與停止狀態，再列出來源檔；來源副本保持原位。
    # 以 .NET 開啟 supervisor.lock，FileShare.None／'None' 禁止其他工具同時開啟：這就是排他鎖。
    # 鎖是保持開啟的檔案 handle；finally 的 Dispose 關閉它才釋放鎖，並非刪掉 lock 檔。
    $lock = [IO.File]::Open((Join-Path $source 'supervisor.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    # Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
    $status = Get-Content -LiteralPath (Join-Path $source 'status.json') -Raw | ConvertFrom-Json
    # -notin 表示值不在允許清單；只有 stopped／paused／success／error 才接受此離線操作。
    if ($status.state -notin @('stopped','paused','success','error')) { throw "Source is not stopped: $($status.state)" }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($name in @('control.json','curriculum.json','curriculum_state.json','model.json','model_source')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name))) { throw "Missing required source: $name" }
    }
    # Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
    $cfg = Get-Content -LiteralPath (Join-Path $source 'control.json') -Raw | ConvertFrom-Json
    if ($cfg.diagnosticDir -and [IO.Path]::GetFullPath([string]$cfg.diagnosticDir).TrimEnd('\') -ne (Join-Path $source 'diagnostics')) {
        throw 'External diagnostics require a separate migration; this tool only supports session-local diagnostics.'
    }
    $items = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
    # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
    if ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source must not be a link.' }
    # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked files/directories are not supported.' }
    $files = @($items | Where-Object { -not $_.PSIsContainer -and $_.FullName -ne (Join-Path $source 'supervisor.lock') })
    $candidates = @($files | Where-Object {
        ($_.Name -eq 'Agent_Final.mat' -or $_.Name -match '^Agent_?\d+\.mat$') -and
        $_.FullName.Substring($source.Length) -notmatch '[\\/]runs[\\/]'
    })
    if (-not $candidates.Count) { throw 'No saved checkpoint found; refusing to migrate an empty training run.' }
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null = New-Item -ItemType Directory -Path $targetParent -Force
    $stage = Join-Path (Split-Path $targetParent -Parent) ('.incoming_' + [guid]::NewGuid().ToString('N'))
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null = New-Item -ItemType Directory -Path $stage
    $manifest = @()
    $n = 0
    # 逐檔複製前後檢查來源／目的 SHA，任何變動都拒絕發布目的副本。
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\','/')
        $dest = Join-Path $stage $relative
        # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
        $null = New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force
        # Get-FileHash -Algorithm SHA256 計算內容指紋，.Hash 取字串供來源與目的逐檔比較。
        $before = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $dest
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $before -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $before) { throw "File changed or copy mismatch: $relative" }
        # @{key=value; ...} 是 hashtable，保存有名稱的欄位；ConvertTo-Json 再把它寫為 JSON 物件。
        $manifest += @{path=$relative;sha256=$before}
        # ++ 將計數器加 1；attempt 是 run 的歷史編號，launched 是本次 supervisor 新啟動次數。
        $n++
        Write-Progress -Activity 'Copy and SHA256 verification' -Status $relative -PercentComplete (100*$n/$files.Count)
    }
    # Historical logs/options remain untouched; only live execution settings change.
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty sessionDir $target
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty modularRoot $root
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty scriptDir (Join-Path $root 'runtime')
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty diagnosticDir (Join-Path $target 'diagnostics')
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty curriculumName $CurriculumName
    # Add-Member -Force 覆寫新副本物件的控制欄位；此處尚在暫存目錄，不會重寫來源 control。
    $cfg | Add-Member -Force NoteProperty resumeAgentFile ''
    # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
    Write-Json (Join-Path $stage 'control.json') $cfg
    # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
    [IO.File]::WriteAllText((Join-Path $stage 'STOP'),'',$utf8)
    # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
    Write-Json (Join-Path $stage 'status.json') @{state='stopped';attempt=$status.attempt;message='Migrated copy; validate checkpoint before resume.';updated=[DateTime]::Now.ToString('o')}
    # WriteAllText／Write-Json 寫完整文字；ConvertTo-Json 的 -Depth 限制巢狀序列化深度，不是檔案大小上限。
    Write-Json (Join-Path $stage 'migration.json') @{source=$source;destination=$target;copiedFiles=$files.Count;verifiedFiles=$manifest;rewrittenFiles=@('control.json','status.json','STOP','migration.json');created=[DateTime]::Now.ToString('o')}
    # Both absolute paths are verified within the intended project; source is preserved.
    if (-not ([IO.Path]::GetFullPath($stage)).StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid staging path.' }
    # 只在所有驗證完成後發布已確認位於專案內的暫存副本。
    # 這一步發布已驗證的暫存副本／檔案；驗證前不把半成品當正式結果。
    Move-Item -LiteralPath $stage -Destination $target
    Write-Progress -Activity 'Copy and SHA256 verification' -Completed
    Write-Output "Migration complete. Original preserved: $source"
    Write-Output "New session: $target"
    Write-Output 'No training started. Run trainingtools.verify_training_session in MATLAB before retry(resume=...).'
# finally 無論成功、return 或例外都執行；Dispose 釋放本次鎖／串流，不代表刪除訓練成果。
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
