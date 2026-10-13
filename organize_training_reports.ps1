# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# 報告整理：在停止狀態及排他鎖下，複製舊報告／圖表到 run/reports。
# 相同目的檔可重跑，不同內容拒絕覆寫；保留原件，不搬 checkpoint 或修改課程狀態。
# param 定義此腳本可接受的命名參數；呼叫者用 -ConfigFile／-SessionPath 等名稱傳值。
# [Parameter(Mandatory=$true)] 表示必填；[ValidatePattern(...)] 在執行主體前驗證字串格式。
param(
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$')][string]$Machine='lab',
    [string]$LegacyReportPath=''
)
# Report-only copy. Never move checkpoints or change curriculum state.
# PowerShell 內建變數：Stop 將可處理的命令錯誤提升成例外，使 try/catch/finally 能接住。
$ErrorActionPreference='Stop'
# Resolve-Path 先確認來源存在；括號取得命令回傳物件，再用 .Path 取路徑字串與 TrimEnd 去尾端分隔符。
$session=(Resolve-Path -LiteralPath $SessionPath).Path.TrimEnd('\','/')
# 先以 $null 初始化資源，finally 用它判斷本次是否真的取得程序／鎖／串流，避免對空值清理。
$lock=$null
# try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
try {
    # 報告整理也需要停止與鎖，防止複製過程中被新的輸出改寫。
    # 以 .NET 開啟 supervisor.lock，FileShare.None／'None' 禁止其他工具同時開啟：這就是排他鎖。
    # 鎖是保持開啟的檔案 handle；finally 的 Dispose 關閉它才釋放鎖，並非刪掉 lock 檔。
    $lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),'Open','ReadWrite','None')
    # Get-Content -Raw 讀成整段文字；管線接 ConvertFrom-Json 轉為物件，可用 .欄位名稱取值。
    $state=Get-Content -LiteralPath (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
    # -notin 表示值不在允許清單；只有 stopped／paused／success／error 才接受此離線操作。
    if ($state.state -notin @('stopped','paused','success','error')) { throw 'Stop training before organizing existing reports.' }
    $destDir=Join-Path $session 'reports'
    # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
    if ((Test-Path -LiteralPath $destDir) -and ((Get-Item -LiteralPath $destDir).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'reports must not be a link.' }
    # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
    $null=New-Item -ItemType Directory -Path $destDir -Force
    $report=$LegacyReportPath
    if (-not $report) { $report=Join-Path $PSScriptRoot "reports\$Machine\$([IO.Path]::GetFileName($session))\report.json" }
    $sources=@(
        @{source=$report;name='report.json'},
        @{source=(Join-Path $session 'reward_history.png');name='reward_history.png'},
        @{source=(Join-Path $session 'reward_history.csv');name='reward_history.csv'}
    )
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    foreach ($item in $sources) {
        $source=$item.source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Write-Output "Not found, skipped: $source"; continue }
        # -band 是位元 AND，檢查屬性是否包含 ReparsePoint；拒絕連結避免來源走到預期範圍之外。
        if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source must not be a link.' }
        if ($item.name -eq 'report.json') {
            $data=Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
            if ($data.session_id -ne [IO.Path]::GetFileName($session) -or $data.machine -ne $Machine) { throw 'Report session/machine does not match this request.' }
        }
        $dest=Join-Path $destDir $item.name
        # Get-FileHash -Algorithm SHA256 計算內容指紋，.Hash 取字串供來源與目的逐檔比較。
        $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        # 目的內容一致則跳過；不一致拒絕覆寫以保留兩份證據。
        if (Test-Path -LiteralPath $dest) {
            if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $hash) {
                throw "Destination has different content; preserved both files. Re-export/plot if the new report is preferred: $dest"
            }
            Write-Output "Already copied: $dest"; continue
        }
        $temporary=Join-Path $destDir ('.copy_' + [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $source -Destination $temporary
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $hash -or
            (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash) { throw "Copy/source changed: $source" }
        # File.Move refuses overwrite and operates only on these report files.
        # 暫存複製和來源均驗證後原子發布，拒絕覆寫已有檔案。
        # 這一步發布已驗證的暫存副本／檔案；驗證前不把半成品當正式結果。
        [IO.File]::Move($temporary,$dest)
        Write-Output "Copied and verified: $dest"
    }
    Write-Output 'Reports organized. Originals retained. Checkpoints/state unchanged; no training started.'
# finally 無論成功、return 或例外都執行；Dispose 釋放本次鎖／串流，不代表刪除訓練成果。
} finally { if ($null -ne $lock) { $lock.Dispose() } }
