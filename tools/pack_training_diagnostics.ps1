# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 診斷打包：鎖住停止 run，選取 checkpoint、初始快照、評估 traces 與設定日誌。
# 產生 ZIP 和逐檔雜湊清單，再讀回驗證；不自動上傳，診斷子集不是完整續訓備份。
# param 定義此腳本可接受的命名參數；呼叫者用 -ConfigFile／-SessionPath 等名稱傳值。
# [Parameter(Mandatory=$true)] 表示必填；[ValidatePattern(...)] 在執行主體前驗證字串格式。
param(
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^evaluation_[A-Za-z0-9_]+$')][string]$EvaluationName,
    [int[]]$Episodes=@(10600,10700),
    [ValidatePattern('^r[0-9]{6}$')][string]$InitialRun='r000001'
)
# Read-only export of a stopped run. No upload, training, or Git mutation.
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference='Stop'
# Add-Type 載入 .NET 壓縮組件，使 ZipArchive／ZipFile 型別可使用，不是下載套件。
Add-Type -AssemblyName System.IO.Compression
# Add-Type 載入 .NET 壓縮組件，使 ZipArchive／ZipFile 型別可使用，不是下載套件。
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Resolve-Path 先確認來源存在；括號取得命令回傳物件，再用 .Path 取路徑字串與 TrimEnd 去尾端分隔符。
$session=(Resolve-Path -LiteralPath $SessionPath).Path.TrimEnd('\','/')
# 先以 $null 初始化資源，finally 用它判斷本次是否真的取得程序／鎖／串流，避免對空值清理。
$lock=$null; $zip=$null; $stream=$null
# New-Object 建立指定 .NET 型別的實例；List[string] 限定存字串，ZipArchive 是此 ZIP 寫入器。
$selected=New-Object 'System.Collections.Generic.List[string]'
# 驗證必需／選用診斷檔與路徑非連結，將相對檔名去重加入 ZIP 清單。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Add-Source([string]$relative,[bool]$required=$true) {
    $file=Join-Path $session $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        if ($required) { throw "Required diagnostic missing: $relative" }
        return
    }
    $item=Get-Item -LiteralPath $file
    while ($null -ne $item -and $item.FullName.Length -ge $session.Length) {
        # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked diagnostic paths are not supported: $relative" }
        if ($item.FullName -eq $session) { break }
        if ($item -is [IO.FileInfo]) { $item=$item.Directory } else { $item=$item.Parent }
    }
    if (-not $selected.Contains($relative)) { $selected.Add($relative) }
}
# try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
try {
    # 停止狀態與排他鎖下選取檔案，來源／父目錄為連結時拒絕。
    # 以 .NET 開啟 supervisor.lock，FileShare.None／'None' 禁止其他工具同時開啟：這就是排他鎖。
    # 鎖是保持開啟的檔案 handle；finally 的 Dispose 關閉它才釋放鎖，並非刪掉 lock 檔。
    $lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),'Open','ReadWrite','None')
    # Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
    $state=Get-Content -LiteralPath (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
    # -notin 表示值不在允許清單；只有 stopped／paused／success／error 才接受此離線操作。
    if ($state.state -notin @('paused','stopped','success','error')) { throw 'Stop training before packing diagnostics.' }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($ep in $Episodes) {
        if ($ep -le 0) { throw 'Episodes must be positive.' }
        Add-Source "checkpoints/Agent$ep.mat"
    }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($name in @('control.json','model.json','curriculum.json','curriculum_state.json','recovery.json','status.json')) { Add-Source $name }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($name in @('training_guard.json','training_guard_state.json','curriculum_outcome.json')) { Add-Source $name $false }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($name in @('Agent_Initial.mat','TrainingOptions.mat','training_script_snapshot.m')) { Add-Source "runs/$InitialRun/$name" }
    $evaluation=Join-Path $session "reports/$EvaluationName"
    Add-Source "reports/$EvaluationName/evaluation.json"
    $result=Get-Content -LiteralPath (Join-Path $evaluation 'evaluation.json') -Raw | ConvertFrom-Json
    if ($result.status -ne 'complete') { throw 'Select a completed evaluation.' }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($row in $result.results) {
        if ($row.trace -notmatch '^ep[0-9]+_stage[0-9]+_seed[0-9]+\.mat$') { throw 'Unexpected evaluation trace name.' }
        Add-Source "reports/$EvaluationName/$($row.trace)"
    }
    Add-Source "reports/$EvaluationName/scenarios.mat" $false
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $session 'reports') -Filter 'resume_audit_*.json' -File) { Add-Source "reports/$($f.Name)" }
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($folder in Get-ChildItem -LiteralPath $session -Directory -Filter 'attempt_*') {
        # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
        foreach ($name in @('stdout.log','stderr.log','result.json','pool_error.json')) { Add-Source "$($folder.Name)/$name" $false }
    }
    $out=Join-Path (Split-Path $PSScriptRoot -Parent) 'diagnostic_packages'
    # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
    if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Output folder must not be a link.' }
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null=New-Item -ItemType Directory -Path $out -Force
    $target=Join-Path $out ('diagnostics_'+[IO.Path]::GetFileName($session)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.zip')
    $partial=$target+'.partial'
    $stream=[IO.File]::Open($partial,'CreateNew','ReadWrite','None')
    # New-Object 建立指定 .NET 型別的實例；List[string] 限定存字串，ZipArchive 是此 ZIP 寫入器。
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    $manifest=@()
    # 建立 ZIP 時檢查來源未變，manifest 只記本次選取的診斷子集。
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($relative in $selected) {
        $source=Join-Path $session $relative
        # Get-FileHash -Algorithm SHA256 計算內容指紋，.Hash 取字串供來源與目的逐檔比較。
        $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$source,$relative.Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash) { throw "Source changed during packing: $relative" }
        # @{key=value; ...} 是 hashtable，保存有名稱的欄位；ConvertTo-Json 再把它寫為 JSON 物件。
        $manifest+=@{path=$relative.Replace('\','/');sha256=$hash;bytes=(Get-Item -LiteralPath $source).Length}
    }
    # CreateEntry 建 ZIP 內檔案；StreamWriter 寫 manifest 文字，Dispose 關閉該 entry 的串流。
    $entry=$zip.CreateEntry('manifest.json'); $writer=New-Object IO.StreamWriter($entry.Open())
    # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
    try { $writer.Write((@{schema_version=1;purpose='diagnostics only; not a resumable session';files=$manifest} | ConvertTo-Json -Depth 6)) } finally { $writer.Dispose() }
    # 先關閉 ZIP 與底層串流，完整目錄結構才可讀回；設成 $null 避免 finally 再清理同一資源。
    $zip.Dispose(); $zip=$null; $stream.Dispose(); $stream=$null
    # 封存完成後逐項讀回 ZIP 計算 SHA，驗證成功才把 .partial 發布成正式 ZIP。
    # OpenRead 重新打開已寫完封存；逐 entry 計算雜湊，確認壓縮後的內容與來源一致。
    $zip=[IO.Compression.ZipFile]::OpenRead($partial)
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($item in $manifest) {
        $entry=$zip.GetEntry($item.path); $inputStream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
        try { $actual=[BitConverter]::ToString($sha.ComputeHash($inputStream)).Replace('-','') } finally { $inputStream.Dispose(); $sha.Dispose() }
        if ($actual -ne $item.sha256) { throw "Archive verification failed: $($item.path)" }
    }
    # 先關閉 ZIP 與底層串流，完整目錄結構才可讀回；設成 $null 避免 finally 再清理同一資源。
    $zip.Dispose(); $zip=$null
    # 這一步發布已驗證的暫存副本／檔案；驗證前不把半成品當正式結果。
    [IO.File]::Move($partial,$target)
    Write-Output "Verified ZIP: $target"
    Write-Output "Files: $($manifest.Count); bytes: $((Get-Item -LiteralPath $target).Length)"
    Write-Output "SHA256: $((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)"
    Write-Output 'Originals retained. No training/upload started. This diagnostic subset is not a resumable session.'
# finally 無論成功、return 或例外都執行；Dispose 釋放本次鎖／串流，不代表刪除訓練成果。
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
    if ($null -ne $lock) { $lock.Dispose() }
}
