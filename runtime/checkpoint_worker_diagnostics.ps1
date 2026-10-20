# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# worker 診斷輔助：生成降級上限計畫、判定下一索引、從完整 episode 日誌列寫入 CSV。
# target 與 actual 分別代表要求上限及實際 pool；去重只針對同一 attempt，不控制訓練。
# Pure selection and log helpers, also exercised without running training.
# 校驗 fallback 正整數、去重排序，只保留小於 target 的備援上限。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Get-WorkerPlan([int]$Target, $Fallback) {
    # ForEach-Object 先驗證 fallback 值，再 Sort-Object -Descending -Unique 由大到小去重。
    $valid = @($Fallback | ForEach-Object {
        if ([double]$_ -lt 1 -or [double]$_ -ne [int]$_) { throw 'fallbackWorkers must contain positive integers.' }
        if ([int]$_ -lt $Target) { [int]$_ }
    } | Sort-Object -Descending -Unique)
    # 陣列 + 陣列是串接；要求的 target 先排第一，後接較小且合法的備援。
    return @($Target) + $valid
}

# 啟動失敗且 pool 未就緒才前進備援索引，其他情況下回到原 target。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Get-NextWorkerIndex([int]$Index, [int]$Count, [bool]$PoolReady, [bool]$StartupFailed) {
    if (-not $PoolReady -and $StartupFailed -and $Index + 1 -lt $Count) { return $Index + 1 }
    return 0
}

# 以共享讀取方式解析完成 console 行，依 Seen 去重後記錄要求／實際 workers。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Save-EpisodeWorkers([string]$StdoutPath, [string]$CsvPath, [int]$Attempt,
    [int]$Target, [int]$Actual, $Seen) {
    if ($Actual -lt 1 -or -not (Test-Path -LiteralPath $StdoutPath)) { return }
    # Start-Process keeps the redirected log open for writing while MATLAB runs.
    # FileShare.ReadWrite -bor Delete 是位元 OR：允許 MATLAB 繼續寫日誌或替換檔案時仍可讀取。
    $stream = [IO.File]::Open($StdoutPath, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader = [IO.StreamReader]::new($stream)
    # try 包住可能失敗的操作，catch 用 $_ 取得本次 ErrorRecord；throw 可將原錯誤繼續交給上層。
    try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
    # Only completed console rows, not worker-local reset counters.
    # foreach ($item in $collection) 逐項處理集合；本輪 $item 代表目前元素，continue 跳下一項。
    # (?m) 讓 ^ 匹配每行起點；s* 接受空白，(d+) 擷取 episode，尾端換行排除未寫完列。
    foreach ($match in [regex]::Matches($content, '(?m)^\s*Episode:\s*(\d+)\s*/\s*\d+[^\r\n]*Episode Q0:[^\r\n]*\r?\n')) {
        $episode = [int]$match.Groups[1].Value
        # HashSet 記住已匯出回合；Contains 為真時 continue，避免同一 attempt 重複寫 CSV。
        if ($Seen.Contains($episode)) { continue }
        # [pscustomobject] 將欄位表轉為資料物件，Export-Csv 可按欄位輸出一列；-Append 保留既有列。
        [pscustomobject]@{Attempt=$Attempt; Episode=$episode; TargetWorkers=$Target;
            ActualWorkers=$Actual; Reduced=($Actual -lt $Target)} |
            Export-Csv -LiteralPath $CsvPath -Append -NoTypeInformation -Encoding UTF8
        # 把不需顯示的回傳物件指派給 $null；命令仍會執行，但不污染呼叫端收到的資料或終端輸出。
        $null = $Seen.Add($episode)
    }
}
