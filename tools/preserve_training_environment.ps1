param(
    [Parameter(Mandatory=$true)][string]$SessionDir,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedModelSha256,
    [string[]]$AdditionalFiles = @()
)
# Run BEFORE updating the remote checkout. Standalone; needs no new MATLAB code.
# Saves CURRENT local bytes, not proof of every historical attempt's environment.
$ErrorActionPreference='Stop'
$session=(Resolve-Path -LiteralPath $SessionDir).Path
$lock=$null
$utf8=[Text.UTF8Encoding]::new($false)
function Assert-FileName([string]$name) {
    if ($name -notmatch '^[^/\\:]+\.(slx|mat|m|sldd)$' -or $name.StartsWith('.') -or $name.EndsWith(' ')) { throw "Invalid dependency filename: $name" }
    if ($name -match '^(Agent.*\.mat|checkpoint_.*\.m|training_engine\.m|retry\.m)$') { throw "Reserved training filename: $name" }
}
try {
    $lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $statusFile=Join-Path $session 'status.json'
    if (-not (Test-Path -LiteralPath $statusFile)) { throw 'Missing status.json. Cannot establish stopped state.' }
    $status=Get-Content -LiteralPath $statusFile -Raw | ConvertFrom-Json
    if ($status.state -notin @('stopped','paused','success','error')) { throw "Run is not stopped: $($status.state)" }
    $manifestFile=Join-Path $session 'environment.json'
    $destination=Join-Path $session 'environment'
    $staging=Join-Path $session 'environment.preparing'
    if (Test-Path -LiteralPath $staging) { throw 'Incomplete environment.preparing exists; inspect it before retrying.' }
    if (Test-Path -LiteralPath $manifestFile) {
        $existing=Get-Content -LiteralPath $manifestFile -Raw|ConvertFrom-Json
        if ($existing.schema_version -ne 1 -or $existing.model_file -ne 'FAFA_Simulation.slx') { throw 'Invalid existing manifest.' }
        $seen=@{}
        foreach($entry in @($existing.files)) {
            Assert-FileName $entry.name
            if ($seen.ContainsKey($entry.name)) { throw 'Duplicate dependency.' }; $seen[$entry.name]=$true
            $actual=(Get-FileHash -LiteralPath (Join-Path $destination $entry.name) -Algorithm SHA256).Hash
            if ($actual -ne $entry.sha256) { throw "Changed snapshot: $($entry.name)" }
        }
        if (-not $seen.ContainsKey('FAFA_Simulation.slx')) { throw 'Missing model in manifest.' }
        if ((Get-FileHash -LiteralPath (Join-Path $destination 'FAFA_Simulation.slx')).Hash -ne $ExpectedModelSha256) { throw 'Existing snapshot does not match expected model.' }
        Write-Output "Verified existing snapshot; unchanged: $manifestFile"
        return
    }
    if (Test-Path -LiteralPath $destination) { throw 'Environment directory without manifest; refusing overwrite.' }
    $cfg=Get-Content -LiteralPath (Join-Path $session 'control.json') -Raw|ConvertFrom-Json
    if (-not [IO.Path]::IsPathRooted([string]$cfg.scriptDir)) { throw 'control.scriptDir must be an existing absolute runtime path.' }
    $source=(Resolve-Path -LiteralPath $cfg.scriptDir).Path
    $model=Join-Path $source 'FAFA_Simulation.slx'
    if ((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ne $ExpectedModelSha256) { throw 'Local SLX differs from expected SHA. No snapshot created.' }
    # Preserve local MAT/data dictionaries conservatively; include external M dependencies explicitly.
    $names=@('FAFA_Simulation.slx') + @(Get-ChildItem -LiteralPath $source -File | Where-Object {$_.Extension -in @('.mat','.sldd')} | ForEach-Object {$_.Name}) + @($AdditionalFiles)
    $names=@($names | Select-Object -Unique)
    $files=@(foreach($name in $names) {
        Assert-FileName $name
        @{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $null=New-Item -ItemType Directory -Path $staging
    foreach($entry in $files) {
        Copy-Item -LiteralPath (Join-Path $source $entry.name) -Destination (Join-Path $staging $entry.name)
        if ((Get-FileHash -LiteralPath (Join-Path $staging $entry.name)).Hash -ne $entry.sha256 -or
            (Get-FileHash -LiteralPath (Join-Path $source $entry.name)).Hash -ne $entry.sha256) { throw 'Source changed or copy verification failed.' }
    }
    $manifest=@{schema_version=1;id=('legacy_'+$ExpectedModelSha256.Substring(0,12).ToLowerInvariant());model_file='FAFA_Simulation.slx';
        provenance='Captured current local runtime before upgrade; historical execution not proven.';
        captured_at=[DateTimeOffset]::Now.ToString('o');files=@($files)}
    # Resolved destination is a fixed child of the verified session. No recursive move/delete.
    [IO.Directory]::Move($staging,$destination)
    [IO.File]::WriteAllText($manifestFile,($manifest|ConvertTo-Json -Depth 8),$utf8)
    Write-Output "Preserved environment: $manifestFile"
    Write-Output 'No checkpoint, control, curriculum, guard or training process was modified.'
} finally { if($null -ne $lock) {$lock.Dispose()} }
