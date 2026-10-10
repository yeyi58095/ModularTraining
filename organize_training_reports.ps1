param(
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$')][string]$Machine='lab',
    [string]$LegacyReportPath=''
)
# Report-only copy. Never move checkpoints or change curriculum state.
$ErrorActionPreference='Stop'
$session=(Resolve-Path -LiteralPath $SessionPath).Path.TrimEnd('\','/')
$lock=$null
try {
    $lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),'Open','ReadWrite','None')
    $state=Get-Content -LiteralPath (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
    if ($state.state -notin @('stopped','paused','success','error')) { throw 'Stop training before organizing existing reports.' }
    $destDir=Join-Path $session 'reports'
    if ((Test-Path -LiteralPath $destDir) -and ((Get-Item -LiteralPath $destDir).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'reports must not be a link.' }
    $null=New-Item -ItemType Directory -Path $destDir -Force
    $report=$LegacyReportPath
    if (-not $report) { $report=Join-Path $PSScriptRoot "reports\$Machine\$([IO.Path]::GetFileName($session))\report.json" }
    $sources=@(
        @{source=$report;name='report.json'},
        @{source=(Join-Path $session 'reward_history.png');name='reward_history.png'},
        @{source=(Join-Path $session 'reward_history.csv');name='reward_history.csv'}
    )
    foreach ($item in $sources) {
        $source=$item.source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Write-Output "Not found, skipped: $source"; continue }
        if ((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source must not be a link.' }
        if ($item.name -eq 'report.json') {
            $data=Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
            if ($data.session_id -ne [IO.Path]::GetFileName($session) -or $data.machine -ne $Machine) { throw 'Report session/machine does not match this request.' }
        }
        $dest=Join-Path $destDir $item.name
        $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
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
        [IO.File]::Move($temporary,$dest)
        Write-Output "Copied and verified: $dest"
    }
    Write-Output 'Reports organized. Originals retained. Checkpoints/state unchanged; no training started.'
} finally { if ($null -ne $lock) { $lock.Dispose() } }
