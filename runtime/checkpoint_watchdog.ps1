# 閱讀語法：$name 是變數；= 存值；$null 表示沒有值，$true／$false 是布林值。
# [string]／[int]／[bool] 是型別標註或轉型；函式呼叫用「名稱 參數」，不是 MATLAB 的括號呼叫。
# @() 把輸出收集成陣列，@{} 是名稱→值的表；| 把左側輸出的物件交給右側命令。
# { } 包住 if／foreach／function 的內容；$_ 是管線當前物件，參數名的 - 前綴不是減號。
# watchdog 純判定：依日誌尾端、是否啟動完成及經過／閒置時間，回傳重啟原因字串。
# 授權錯誤優先，其次啟動逾時與日誌停滯；此檔本身不啟動或終止任何程序。
# Read-only checks; never inspect or close arbitrary desktop windows.
# 回傳 license_error／startup_timeout／log_stall_timeout 或空字串，呼叫端決定是否恢復。
# function 宣告可重複呼叫的命令；參數中的 [型別] 會檢查或轉換傳入值。
# PowerShell 函式的未被接住輸出會進入成功輸出流；這裡用 return 表達要交回的結果。
function Get-CheckpointWatchdogReason {
    # param 定義此腳本可接受的命名參數；呼叫者用 -ConfigFile／-SessionPath 等名稱傳值。
    # [Parameter(Mandatory=$true)] 表示必填；[ValidatePattern(...)] 在執行主體前驗證字串格式。
    param([string]$LogTail, [bool]$StartupComplete, [double]$ElapsedSeconds,
        [double]$IdleSeconds, [double]$StartupTimeoutSeconds, [double]$StallTimeoutSeconds)
    # (?i) 是 regex 忽略大小寫；| 在此單引號 regex 內是候選模式，不是 PowerShell 管線。
    if ($LogTail -match '(?i)(Licensing\s+Error\s*:?\s*5008|You are not licensed to use\s+R\d{4}[ab]|License checkout failed)') {
        return 'license_error'
    }
    # -gt／-ge 表示大於／大於等於；逾時值為 0 代表停用這項逾時判斷。
    if (-not $StartupComplete -and $StartupTimeoutSeconds -gt 0 -and $ElapsedSeconds -ge $StartupTimeoutSeconds) {
        return 'startup_timeout'
    }
    # -gt／-ge 表示大於／大於等於；逾時值為 0 代表停用這項逾時判斷。
    if ($StartupComplete -and $StallTimeoutSeconds -gt 0 -and $IdleSeconds -ge $StallTimeoutSeconds) {
        return 'log_stall_timeout'
    }
    return ''
}
