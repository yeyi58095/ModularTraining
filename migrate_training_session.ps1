param(
    [Parameter(Mandatory=$true)][string]$SourceSession,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string]$CurriculumName
)
# Copy, verify, then publish. Never delete or rewrite the original experiment.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$source = (Resolve-Path -LiteralPath $SourceSession).Path.TrimEnd('\','/')
$targetParent = Join-Path (Join-Path (Join-Path $root 'experiments') $CurriculumName) 'runs'
$target = [IO.Path]::GetFullPath((Join-Path $targetParent ([IO.Path]::GetFileName($source))))
if (-not $target.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination outside project.' }
if ($target.StartsWith($source + '\',[StringComparison]::OrdinalIgnoreCase) -or $target -eq $source) { throw 'Destination must not be inside source.' }
if (Test-Path -LiteralPath $target) { throw "Destination already exists; refusing overwrite: $target" }
$lock = $null
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Json($path,$value) { [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 50),$utf8) }
try {
    $lock = [IO.File]::Open((Join-Path $source 'supervisor.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $status = Get-Content -LiteralPath (Join-Path $source 'status.json') -Raw | ConvertFrom-Json
    if ($status.state -notin @('stopped','paused','success','error')) { throw "Source is not stopped: $($status.state)" }
    foreach ($name in @('control.json','curriculum.json','curriculum_state.json','model.json','model_source')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name))) { throw "Missing required source: $name" }
    }
    $cfg = Get-Content -LiteralPath (Join-Path $source 'control.json') -Raw | ConvertFrom-Json
    if ($cfg.diagnosticDir -and [IO.Path]::GetFullPath([string]$cfg.diagnosticDir).TrimEnd('\') -ne (Join-Path $source 'diagnostics')) {
        throw 'External diagnostics require a separate migration; this tool only supports session-local diagnostics.'
    }
    $items = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
    if ((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source must not be a link.' }
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked files/directories are not supported.' }
    $files = @($items | Where-Object { -not $_.PSIsContainer -and $_.FullName -ne (Join-Path $source 'supervisor.lock') })
    $candidates = @($files | Where-Object {
        ($_.Name -eq 'Agent_Final.mat' -or $_.Name -match '^Agent_?\d+\.mat$') -and
        $_.FullName.Substring($source.Length) -notmatch '[\\/]runs[\\/]'
    })
    if (-not $candidates.Count) { throw 'No saved checkpoint found; refusing to migrate an empty training run.' }
    $null = New-Item -ItemType Directory -Path $targetParent -Force
    $stage = Join-Path (Split-Path $targetParent -Parent) ('.incoming_' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $stage
    $manifest = @()
    $n = 0
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($source.Length).TrimStart('\','/')
        $dest = Join-Path $stage $relative
        $null = New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force
        $before = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $file.FullName -Destination $dest
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $before -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $before) { throw "File changed or copy mismatch: $relative" }
        $manifest += @{path=$relative;sha256=$before}
        $n++
        Write-Progress -Activity 'Copy and SHA256 verification' -Status $relative -PercentComplete (100*$n/$files.Count)
    }
    # Historical logs/options remain untouched; only live execution settings change.
    $cfg | Add-Member -Force NoteProperty sessionDir $target
    $cfg | Add-Member -Force NoteProperty modularRoot $root
    $cfg | Add-Member -Force NoteProperty scriptDir (Join-Path $root 'runtime')
    $cfg | Add-Member -Force NoteProperty diagnosticDir (Join-Path $target 'diagnostics')
    $cfg | Add-Member -Force NoteProperty curriculumName $CurriculumName
    $cfg | Add-Member -Force NoteProperty resumeAgentFile ''
    Write-Json (Join-Path $stage 'control.json') $cfg
    [IO.File]::WriteAllText((Join-Path $stage 'STOP'),'',$utf8)
    Write-Json (Join-Path $stage 'status.json') @{state='stopped';attempt=$status.attempt;message='Migrated copy; validate checkpoint before resume.';updated=[DateTime]::Now.ToString('o')}
    Write-Json (Join-Path $stage 'migration.json') @{source=$source;destination=$target;copiedFiles=$files.Count;verifiedFiles=$manifest;rewrittenFiles=@('control.json','status.json','STOP','migration.json');created=[DateTime]::Now.ToString('o')}
    # Both absolute paths are verified within the intended project; source is preserved.
    if (-not ([IO.Path]::GetFullPath($stage)).StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid staging path.' }
    Move-Item -LiteralPath $stage -Destination $target
    Write-Progress -Activity 'Copy and SHA256 verification' -Completed
    Write-Output "Migration complete. Original preserved: $source"
    Write-Output "New session: $target"
    Write-Output 'No training started. Run verify_training_session in MATLAB before retry(resume=...).'
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
