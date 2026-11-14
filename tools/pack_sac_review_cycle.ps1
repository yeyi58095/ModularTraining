# Narrow export: this cycle plus its ONE child only. No historical SAC scan.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$root=Split-Path $PSScriptRoot -Parent
$bundle=Join-Path $root 'artifacts/packages/sac-review-cycle-20261114'
if (-not (Test-Path -LiteralPath $bundle -PathType Container)) { throw 'No review bundle exists.' }
$cycleLock=[IO.File]::Open((Join-Path $bundle 'cycle.lock'),'OpenOrCreate','ReadWrite','None')
$childLock=$null; $archive=$null
$files=New-Object 'System.Collections.Generic.List[object]'
$issues=New-Object 'System.Collections.Generic.List[string]'
function Add-Tree([string]$path,[string]$prefix,[bool]$allFiles) {
    $stack=New-Object 'System.Collections.Generic.Stack[string]'; $stack.Push($path)
    while($stack.Count) {
        $folder=$stack.Pop()
        foreach($item in @(Get-ChildItem -LiteralPath $folder -Force)) {
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $issues.Add("Linked path skipped: $($item.FullName)"); continue }
            if($item.PSIsContainer) {
                if($item.Name -in @('slprj','model_source','environment','health_candidates','runs')) { continue }
                $stack.Push($item.FullName); continue
            }
            if($item.Extension -in @('.lock','.zip','.partial')) { continue }
            $isCheckpoint=$item.Name -eq 'Agent_Final.mat' -or $item.Directory.Name -eq 'checkpoints'
            if(-not $allFiles -and $item.Extension -notin @('.json','.log','.csv','.txt') -and -not $isCheckpoint) { continue }
            if($item.Length -gt 256MB) { $issues.Add("Over 256 MiB skipped: $($item.FullName)"); continue }
            $relative=$item.FullName.Substring($path.Length+1).Replace('\','/')
            $files.Add([pscustomobject]@{source=$item.FullName;entry="$prefix/$relative";sha256='';bytes=0})
        }
    }
}
try {
    $summary=New-Object 'System.Collections.Generic.List[string]'
    $summary.Add('# SAC review cycle results')
    $ledgerFile=Join-Path $bundle 'cycle.json'
    if(Test-Path -LiteralPath $ledgerFile){
        $state=Get-Content -LiteralPath $ledgerFile -Raw|ConvertFrom-Json
        $summary.Add("Cycle phase: $($state.phase). This is cycle completion, not curriculum success.")
        $summary.Add("Selected episode: $($state.selected_episode); child: $($state.child)")
        $summary.Add("Added episodes: $($state.added_episodes) / 500; last training reason: $($state.training_stop_reason)")
        if($state.final_state){$summary.Add("Final stage index: $($state.final_state.stage_index)")}
        if($state.error){$summary.Add("Error: $($state.error)")}
    }
    $selection=Join-Path $bundle 'selection.json'
    if(Test-Path -LiteralPath $selection){
        $d=Get-Content -LiteralPath $selection -Raw|ConvertFrom-Json
        $summary.Add('');$summary.Add('## (1) Frozen checkpoint selection');$summary.Add($d.rule)
        $summary.Add('');$summary.Add('| Episode | Calm full / 10 | Weak stage full / 10 | Actual wind full / count | Eligible |')
        $summary.Add('|---|---|---|---|---|')
        foreach($m in $d.metrics){$summary.Add("| $($m.episode) | $($m.full_counts[0]) | $($m.full_counts[1]) | $($m.actual_wind_full) / $($m.actual_wind_count) | $($m.eligible) |")}
    }
    $summary.Add('');$summary.Add('## (2) Bounded training and final evaluation')
    $summary.Add('See holdout.json for the independent candidate check, training_summary.json for new episode windows, gate_*.json for original stage gates, and final_evaluation/evaluation.json for the fixed final policy. Missing files mean the phase was not completed; no results are inferred.')
    $summary.Add('No candidate/failed holdout means no training. Training budget, errors and guards remain active. Check cycle.json and child status before any future continuation.')
    [IO.File]::WriteAllLines((Join-Path $bundle 'RESULTS.md'),$summary.ToArray(),[Text.UTF8Encoding]::new($false))
    Add-Tree $bundle 'cycle' $true
    $ledgerFile=Join-Path $bundle 'cycle.json'
    if(Test-Path -LiteralPath $ledgerFile) {
        $ledger=Get-Content -LiteralPath $ledgerFile -Raw | ConvertFrom-Json
        if($ledger.child) {
            $child=[IO.Path]::GetFullPath([string]$ledger.child)
            $allowed=[IO.Path]::GetFullPath((Join-Path $root 'experiments/sac_random_route_v1/runs'))+'\'
            if(-not $child.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or
                (Get-Item -LiteralPath $child).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected child path.' }
            try { $childLock=[IO.File]::Open((Join-Path $child 'supervisor.lock'),'Open','ReadWrite','None') }
            catch { $issues.Add('Child still locked: exported cycle only; rerun -PackageOnly after it stops.') }
            if($null -ne $childLock) { Add-Tree $child 'child' $false }
        }
    }
    $name='sac-review-cycle-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.zip'
    $target=Join-Path (Split-Path $bundle -Parent) $name
    $partial=$target+'.partial'
    $archive=[IO.Compression.ZipFile]::Open($partial,[IO.Compression.ZipArchiveMode]::Create)
    $n=0
    foreach($f in $files) {
        # Both cycle and child are locked. No active run is copied as a backup.
        $f.sha256=(Get-FileHash -LiteralPath $f.source -Algorithm SHA256).Hash
        $f.bytes=(Get-Item -LiteralPath $f.source).Length
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$f.source,$f.entry,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
        $n++; if($n % 25 -eq 0) { Write-Output "Packing $n/$($files.Count) files" }
    }
    $manifest=@{schema_version=1;scope='Only review cycle and its selected child; not a complete resumable backup';
        files=@($files.ToArray());issues=@($issues.ToArray());collected_at=(Get-Date).ToString('o')}
    $writer=[IO.StreamWriter]::new($archive.CreateEntry('manifest.json').Open())
    try {$writer.Write(($manifest|ConvertTo-Json -Depth 8))} finally {$writer.Dispose()}
    $archive.Dispose(); $archive=$null
    Write-Output "Verifying $($files.Count) files..."
    $archive=[IO.Compression.ZipFile]::OpenRead($partial)
    foreach($f in $files) {
        $entry=$archive.GetEntry($f.entry)
        if($null -eq $entry -or $entry.Length -ne $f.bytes){throw "Archive length mismatch: $($f.entry)"}
        $stream=$entry.Open(); $sha=[Security.Cryptography.SHA256]::Create()
        try {$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}
        finally {$stream.Dispose();$sha.Dispose()}
        if($actual -ne $f.sha256){throw "Archive hash mismatch: $($f.entry)"}
    }
    $archive.Dispose();$archive=$null
    Move-Item -LiteralPath $partial -Destination $target
    $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    [IO.File]::WriteAllText(($target+'.sha256'),$hash+'  '+$name)
    Write-Output "Verified ZIP: $target"
    Write-Output "SHA256: $hash"
    foreach($issue in $issues){Write-Warning $issue}
} finally {
    if($null -ne $archive){$archive.Dispose()}
    if($null -ne $childLock){$childLock.Dispose()}
    $cycleLock.Dispose()
}
