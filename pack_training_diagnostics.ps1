param(
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^evaluation_[A-Za-z0-9_]+$')][string]$EvaluationName,
    [int[]]$Episodes=@(10600,10700),
    [ValidatePattern('^r[0-9]{6}$')][string]$InitialRun='r000001'
)
# Read-only export of a stopped run. No upload, training, or Git mutation.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$session=(Resolve-Path -LiteralPath $SessionPath).Path.TrimEnd('\','/')
$lock=$null; $zip=$null; $stream=$null
$selected=New-Object 'System.Collections.Generic.List[string]'
function Add-Source([string]$relative,[bool]$required=$true) {
    $file=Join-Path $session $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        if ($required) { throw "Required diagnostic missing: $relative" }
        return
    }
    $item=Get-Item -LiteralPath $file
    while ($null -ne $item -and $item.FullName.Length -ge $session.Length) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked diagnostic paths are not supported: $relative" }
        if ($item.FullName -eq $session) { break }
        if ($item -is [IO.FileInfo]) { $item=$item.Directory } else { $item=$item.Parent }
    }
    if (-not $selected.Contains($relative)) { $selected.Add($relative) }
}
try {
    $lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),'Open','ReadWrite','None')
    $state=Get-Content -LiteralPath (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
    if ($state.state -notin @('paused','stopped','success','error')) { throw 'Stop training before packing diagnostics.' }
    foreach ($ep in $Episodes) {
        if ($ep -le 0) { throw 'Episodes must be positive.' }
        Add-Source "checkpoints/Agent$ep.mat"
    }
    foreach ($name in @('control.json','model.json','curriculum.json','curriculum_state.json','recovery.json','status.json')) { Add-Source $name }
    foreach ($name in @('training_guard.json','training_guard_state.json','curriculum_outcome.json')) { Add-Source $name $false }
    foreach ($name in @('Agent_Initial.mat','TrainingOptions.mat','training_script_snapshot.m')) { Add-Source "runs/$InitialRun/$name" }
    $evaluation=Join-Path $session "reports/$EvaluationName"
    Add-Source "reports/$EvaluationName/evaluation.json"
    $result=Get-Content -LiteralPath (Join-Path $evaluation 'evaluation.json') -Raw | ConvertFrom-Json
    if ($result.status -ne 'complete') { throw 'Select a completed evaluation.' }
    foreach ($row in $result.results) {
        if ($row.trace -notmatch '^ep[0-9]+_stage[0-9]+_seed[0-9]+\.mat$') { throw 'Unexpected evaluation trace name.' }
        Add-Source "reports/$EvaluationName/$($row.trace)"
    }
    Add-Source "reports/$EvaluationName/scenarios.mat" $false
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $session 'reports') -Filter 'resume_audit_*.json' -File) { Add-Source "reports/$($f.Name)" }
    foreach ($folder in Get-ChildItem -LiteralPath $session -Directory -Filter 'attempt_*') {
        foreach ($name in @('stdout.log','stderr.log','result.json','pool_error.json')) { Add-Source "$($folder.Name)/$name" $false }
    }
    $out=Join-Path $PSScriptRoot 'diagnostic_packages'
    if ((Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Output folder must not be a link.' }
    $null=New-Item -ItemType Directory -Path $out -Force
    $target=Join-Path $out ('diagnostics_'+[IO.Path]::GetFileName($session)+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.zip')
    $partial=$target+'.partial'
    $stream=[IO.File]::Open($partial,'CreateNew','ReadWrite','None')
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    $manifest=@()
    foreach ($relative in $selected) {
        $source=Join-Path $session $relative
        $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$source,$relative.Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $hash) { throw "Source changed during packing: $relative" }
        $manifest+=@{path=$relative.Replace('\','/');sha256=$hash;bytes=(Get-Item -LiteralPath $source).Length}
    }
    $entry=$zip.CreateEntry('manifest.json'); $writer=New-Object IO.StreamWriter($entry.Open())
    try { $writer.Write((@{schema_version=1;purpose='diagnostics only; not a resumable session';files=$manifest} | ConvertTo-Json -Depth 6)) } finally { $writer.Dispose() }
    $zip.Dispose(); $zip=$null; $stream.Dispose(); $stream=$null
    $zip=[IO.Compression.ZipFile]::OpenRead($partial)
    foreach ($item in $manifest) {
        $entry=$zip.GetEntry($item.path); $inputStream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try { $actual=[BitConverter]::ToString($sha.ComputeHash($inputStream)).Replace('-','') } finally { $inputStream.Dispose(); $sha.Dispose() }
        if ($actual -ne $item.sha256) { throw "Archive verification failed: $($item.path)" }
    }
    $zip.Dispose(); $zip=$null
    [IO.File]::Move($partial,$target)
    Write-Output "Verified ZIP: $target"
    Write-Output "Files: $($manifest.Count); bytes: $((Get-Item -LiteralPath $target).Length)"
    Write-Output "SHA256: $((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)"
    Write-Output 'Originals retained. No training/upload started. This diagnostic subset is not a resumable session.'
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
    if ($null -ne $lock) { $lock.Dispose() }
}
