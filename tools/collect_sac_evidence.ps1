param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutputDirectory = '',
    [switch]$Preview,
    [switch]$IncludeCheckpoints,
    [switch]$IncludeEvaluationTraces,
    [switch]$IncludeArchives,
    [ValidateRange(0,1048576)][double]$MaxFileMB = 256
)
# Read-only, dependency-free Windows PowerShell 5.1 collector. Does not lock,
# pause, resume, delete, or alter any run. Live evidence is explicitly non-atomic.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\','/')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'artifacts/packages/sac-evidence' }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $root $OutputDirectory }
$out = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
$issues = New-Object 'System.Collections.Generic.List[object]'
$runs = New-Object 'System.Collections.Generic.List[object]'
$files = New-Object 'System.Collections.Generic.List[object]'
$seen = @{}
$pruned = @('slprj','node_modules','__pycache__','.git','.venv','venv','cache','caches')

function Relative([string]$path) {
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Source outside project: $path"
    }
    return $path.Substring($root.Length+1).Replace('\','/')
}
function Is-Link($item) { return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) }
function Check-Ancestors([string]$path) {
    $current = $path
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (Is-Link $item) { throw "Linked path is not supported: $current" }
        }
        $current = Split-Path -Parent $current
    }
}
Check-Ancestors $root
Check-Ancestors $out
# Keep the output out of every scanned source tree, including prior intake data.
if (-not $out.StartsWith($root + '\artifacts\packages\',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must be a directory under PROJECT/artifacts/packages/.'
}
function Read-Json([string]$path) {
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { $issues.Add(@{path=(Relative $path);reason='unreadable_json';message=$_.Exception.Message}); return $null }
}
function Property($object,[string]$key) {
    if ($null -ne $object -and $null -ne $object.PSObject.Properties[$key]) { return $object.$key }
    return $null
}
function Add-Tree([string]$folder,[string]$scope,[string]$runId) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return }
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($folder)
    while ($stack.Count) {
        $dir = $stack.Pop()
        $item = Get-Item -LiteralPath $dir -Force
        if (Is-Link $item) { $issues.Add(@{path=(Relative $dir);reason='linked_directory_skipped'}); continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Force | Sort-Object Name)) {
            if (Is-Link $f) { $issues.Add(@{path=(Relative $f.FullName);reason='linked_path_skipped'}); continue }
            if ($f.PSIsContainer) {
                if ($f.Name -in $pruned -or $f.Name -match '_rtw$') {
                    $issues.Add(@{path=(Relative $f.FullName);reason='generated_cache_directory_skipped'})
                } else { $stack.Push($f.FullName) }
                continue
            }
            Add-File $f $scope $runId
        }
    }
}
function Add-File($f,[string]$scope,[string]$runId) {
    $rel = Relative $f.FullName
    if ($seen.ContainsKey($rel)) { return }
    $seen[$rel] = $true
    $reason = ''
    $ext = $f.Extension.ToLowerInvariant()
    if ($f.Name -match '\.lock$') { $reason = 'lock_file_not_copied' }
    elseif ($ext -in @('.slxc','.pyc','.mexw64','.dll','.exe','.dmp')) { $reason = 'generated_binary_or_dump' }
    elseif ($ext -in @('.zip','.rar','.7z') -and -not $IncludeArchives) { $reason = 'existing_archive_use_IncludeArchives' }
    elseif ($ext -eq '.mat') {
        # Checkpoint, replay and optimizer MATs stay excluded unless requested.
        # Evaluation traces are separately opt-in and restricted to report trees.
        $isTrace = $rel -match '/(reports|evaluations)/' -and $f.Name -match '^(ep\d+_stage\d+_seed\d+|scenarios)\.mat$'
        if (-not $IncludeCheckpoints -and -not ($IncludeEvaluationTraces -and $isTrace)) {
            $reason = 'mat_use_IncludeEvaluationTraces_or_IncludeCheckpoints'
        }
    }
    if (-not $reason -and $MaxFileMB -gt 0 -and $f.Length -gt $MaxFileMB*1MB) { $reason = 'over_MaxFileMB' }
    $files.Add([pscustomobject][ordered]@{path=$rel;source=$f.FullName;scope=$scope;run_id=$runId;
        bytes_at_discovery=$f.Length;included=(!$reason);exclusion_reason=$reason;sha256=$null;bytes_exported=$null;changed_during_copy=$null;last_write_utc_at_copy=$null})
}

# Discover only structural run roots, never recursively select model_source fixtures
# or follow group junctions. Algorithm metadata, not "latest run", selects SAC.
$containers = New-Object 'System.Collections.Generic.List[string]'
foreach ($base in @('experiments','+trainingmodels')) {
    $path = Join-Path $root $base
    if (Test-Path -LiteralPath $path -PathType Container) {
        Check-Ancestors $path
        foreach ($p in @(Get-ChildItem -LiteralPath $path -Directory | Sort-Object Name)) {
            if (Is-Link $p) { continue }
            $c = Join-Path $p.FullName 'runs'
            if (Test-Path -LiteralPath $c -PathType Container) { Check-Ancestors $c; $containers.Add($c) }
        }
    }
}
foreach ($c in @('sessions','runtime/training_runs_parallel_checkpointed')) {
    $path=Join-Path $root $c
    if (Test-Path -LiteralPath $path -PathType Container) { Check-Ancestors $path; $containers.Add($path) }
}
foreach ($container in $containers) {
    foreach ($d in @(Get-ChildItem -LiteralPath $container -Directory -Force | Sort-Object Name)) {
        if (Is-Link $d) { $issues.Add(@{path=(Relative $d.FullName);reason='linked_run_skipped'}); continue }
        $modelPath = Join-Path $d.FullName 'model.json'
        if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
            $issues.Add(@{path=(Relative $d.FullName);reason='no_model_json_not_classified'}); continue
        }
        if (Is-Link (Get-Item -LiteralPath $modelPath -Force)) {
            $issues.Add(@{path=(Relative $modelPath);reason='linked_model_skipped'}); continue
        }
        $model = Read-Json $modelPath
        if ($null -eq $model) { continue }
        $algorithm = [string](Property $model 'algorithm')
        $modelName = [string](Property $model 'name')
        if ($algorithm -ne 'SAC' -and -not ($algorithm -eq '' -and $modelName -match '^sac(_|$)')) { continue }
        $state = 'unknown'
        $statusPath=Join-Path $d.FullName 'status.json'
        if (Test-Path -LiteralPath $statusPath -PathType Leaf) {
            if (Is-Link (Get-Item -LiteralPath $statusPath -Force)) {
                $issues.Add(@{path=(Relative $statusPath);reason='linked_status_skipped'})
            } else { $state=[string](Property (Read-Json $statusPath) 'state') }
        }
        $recovery = $null
        $recoveryPath=Join-Path $d.FullName 'recovery.json'
        if (Test-Path -LiteralPath $recoveryPath -PathType Leaf) {
            if (-not (Is-Link (Get-Item -LiteralPath $recoveryPath -Force))) { $recovery=Read-Json $recoveryPath }
        }
        $parent=[string](Property $recovery 'parent_session')
        $parentId = ($parent.TrimEnd('\','/') -split '[\\/]')[-1]
        $attempts=@(foreach ($a in @(Get-ChildItem -LiteralPath $d.FullName -Directory | Where-Object Name -match '^attempt_?\d+$' | Sort-Object Name)) {
            if (Is-Link $a) { continue }
            [ordered]@{name=$a.Name;path=(Relative $a.FullName);
                stdout_present=(Test-Path -LiteralPath (Join-Path $a.FullName 'stdout.log') -PathType Leaf);
                stderr_present=(Test-Path -LiteralPath (Join-Path $a.FullName 'stderr.log') -PathType Leaf);
                result_present=(Test-Path -LiteralPath (Join-Path $a.FullName 'result.json') -PathType Leaf)}
        })
        $runs.Add([pscustomobject][ordered]@{run_id=$d.Name;path=(Relative $d.FullName);model=$modelName;
            algorithm=$algorithm;state_at_discovery=$state;
            consistency='read_only_per_file_snapshot_not_atomic_run_backup';
            parent_session_recorded=$parent;parent_run_id=$parentId;
            parent_episode=(Property $recovery 'parent_episode');
            parent_sha256=(Property $recovery 'parent_sha256');
            attempt_count=$attempts.Count;attempts=$attempts})
        Add-Tree $d.FullName 'run' $d.Name
    }
}
if ($runs.Count -eq 0) { throw 'No SAC runs with identifiable model.json found. Nothing was exported.' }
foreach ($r in $runs) {
    if ($r.parent_run_id) {
        $matches=@($runs | Where-Object run_id -eq $r.parent_run_id)
        if ($matches.Count -ne 1) {
            $issues.Add(@{path=$r.path;reason='parent_missing_or_ambiguous';parent_run_id=$r.parent_run_id;matches=$matches.Count})
        }
    }
}
# Include shared configuration, receipts, prior unpacked SAC evidence, and relevant
# code/docs. Existing archives and MATs still obey the explicit switches above.
foreach ($pattern in @('configs/sac*.json','configs/*sac*.json','docs/records/sac*.md','docs/guides/sac*.md',
    'tools/*sac*','+trainingtools/*sac*.m','artifacts/sac*','*sac*.log','*sac*.csv','*sac*.json','*sac*.txt','*sac*.zip')) {
    foreach ($f in @(Get-ChildItem -Path (Join-Path $root $pattern) -File -ErrorAction SilentlyContinue)) {
        if (-not (Is-Link $f)) { Check-Ancestors $f.FullName; Add-File $f 'shared_context' '' }
    }
}
foreach ($base in @('curricula','artifacts/incoming','+trainingmodels')) {
    $path=Join-Path $root $base
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $path -Directory | Where-Object Name -match '^sac')) {
        # Model definitions only: raw model runs were already collected above.
        if ($base -eq '+trainingmodels') {
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -File)) {
                if (-not (Is-Link $f)) { Check-Ancestors $f.FullName; Add-File $f 'model_definition' '' }
            }
        } else { Check-Ancestors $d.FullName; Add-Tree $d.FullName 'shared_context' '' }
    }
}
$rootIntake=Join-Path $root 'artifacts/incoming/root-intake-20261025'
if (Test-Path -LiteralPath $rootIntake) {
    Check-Ancestors $rootIntake
    foreach ($d in @(Get-ChildItem -LiteralPath $rootIntake -Directory | Where-Object Name -match '^sac')) {
        Check-Ancestors $d.FullName; Add-Tree $d.FullName 'shared_context' ''
    }
}
$chosen=@($files | Where-Object included)
$total=($chosen | Measure-Object bytes_at_discovery -Sum).Sum
Write-Output "SAC runs: $($runs.Count); attempts: $(($runs | Measure-Object attempt_count -Sum).Sum)"
foreach ($r in $runs) { Write-Output "  $($r.model) | $($r.state_at_discovery) | attempts=$($r.attempt_count) | $($r.path)" }
Write-Output "Selected files: $($chosen.Count); source bytes: $total; excluded files: $($files.Count-$chosen.Count); discovery issues: $($issues.Count)"
if ($Preview) {
    Write-Output 'Preview only. No files, locks, directories, or packages created.'
    foreach ($g in @($files | Where-Object { -not $_.included } | Group-Object exclusion_reason)) { Write-Output "  Excluded $($g.Count): $($g.Name)" }
    return
}

$null=New-Item -ItemType Directory -Path $out -Force
$name='sac-evidence-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$target=Join-Path $out ($name+'.zip')
$partial=$target+'.partial'
$zip=$null; $stream=$null
function Write-TextEntry($archive,[string]$name,[string]$text) {
    $writer=New-Object IO.StreamWriter($archive.CreateEntry($name).Open(),(New-Object Text.UTF8Encoding($false)))
    try { $writer.Write($text) } finally { $writer.Dispose() }
}
try {
    $stream=[IO.File]::Open($partial,'CreateNew','ReadWrite','None')
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach ($f in $chosen) {
        # Bound each live read to the original length. Appending stdout cannot make
        # this loop run forever; length/time changes are explicitly recorded.
        Check-Ancestors $f.source
        $sourceStream=$null; $entryStream=$null; $sha=$null
        try {
            $before=Get-Item -LiteralPath $f.source -Force
            $length=$before.Length; $ticks=$before.LastWriteTimeUtc.Ticks
            if ($MaxFileMB -gt 0 -and $length -gt $MaxFileMB*1MB) {
                throw "Source grew over MaxFileMB after discovery; rerun preview: $($f.path)"
            }
            $sourceStream=[IO.File]::Open($f.source,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $entryStream=$zip.CreateEntry('evidence/'+$f.path,[IO.Compression.CompressionLevel]::Optimal).Open()
            $sha=[Security.Cryptography.SHA256]::Create()
            $buffer=New-Object byte[] (1MB)
            [long]$copied=0
            while ($copied -lt $length) {
                $n=$sourceStream.Read($buffer,0,[int][Math]::Min($buffer.Length,$length-$copied))
                if ($n -eq 0) { break }
                $entryStream.Write($buffer,0,$n)
                $null=$sha.TransformBlock($buffer,0,$n,$buffer,0)
                $copied+=$n
            }
            $null=$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
            $f.sha256=[BitConverter]::ToString($sha.Hash).Replace('-','').ToLowerInvariant()
            $f.bytes_exported=$copied
            $after=Get-Item -LiteralPath $f.source -Force
            $f.changed_during_copy=($copied -ne $length -or $after.Length -ne $length -or $after.LastWriteTimeUtc.Ticks -ne $ticks)
            $f.last_write_utc_at_copy=$before.LastWriteTimeUtc.ToString('o')
            if ($f.changed_during_copy) { $issues.Add(@{path=$f.path;reason='source_changed_during_copy_non_atomic_snapshot'}) }
        } finally {
            if ($null -ne $entryStream) { $entryStream.Dispose() }
            if ($null -ne $sourceStream) { $sourceStream.Dispose() }
            if ($null -ne $sha) { $sha.Dispose() }
        }
    }
    $manifest=[ordered]@{schema_version=1;purpose='SAC historical evidence, not a resumable run backup';
        project_root=$root;collected_at=(Get-Date).ToString('o');
        consistency='Per-file snapshot. Never an atomic multi-file/run snapshot, even if discovery state says paused.';
        options=@{include_checkpoints=[bool]$IncludeCheckpoints;include_evaluation_traces=[bool]$IncludeEvaluationTraces;
            include_archives=[bool]$IncludeArchives;max_file_mb=$MaxFileMB};
        runs=@($runs.ToArray());files=@($files.ToArray());issues=@($issues.ToArray())}
    $manifestText=$manifest | ConvertTo-Json -Depth 14
    Write-TextEntry $zip 'manifest.json' $manifestText
    Write-TextEntry $zip 'README.txt' @"
SAC + LSTM / pure SAC historical evidence
Original project-relative paths are under evidence/. No source was moved or edited.
manifest.json lists ALL considered files, exclusions, run IDs, lineage, SHA256,
and any detected changes while copying. No models are loaded; no training runs.
Active run logs are best-effort per-file snapshots, NOT atomic training state.
This is NOT a resumable backup, including when -IncludeCheckpoints was requested.
Only existing evidence is collected. No missing loss history/evaluation is generated.
"@
    $zip.Dispose();$zip=$null;$stream.Dispose();$stream=$null
    # Verify every payload after compression; publish only a fully readable ZIP.
    $zip=[IO.Compression.ZipFile]::OpenRead($partial)
    foreach ($f in $chosen) {
        $entry=$zip.GetEntry('evidence/'+$f.path)
        if ($null -eq $entry -or $entry.Length -ne $f.bytes_exported) { throw "Archive length mismatch: $($f.path)" }
        $entryStream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try { $actual=[BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-','').ToLowerInvariant() }
        finally { $entryStream.Dispose();$sha.Dispose() }
        if ($actual -ne $f.sha256) { throw "Archive SHA mismatch: $($f.path)" }
    }
    $zip.Dispose();$zip=$null
    [IO.File]::Move($partial,$target)
    [IO.File]::WriteAllText((Join-Path $out ($name+'.manifest.json')),$manifestText,(New-Object Text.UTF8Encoding($false)))
    $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    [IO.File]::WriteAllText(($target+'.sha256'),($hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($target)+[Environment]::NewLine))
    Write-Output "Verified ZIP: $target"
    Write-Output "SHA256: $hash"
    Write-Output "Archive bytes: $((Get-Item -LiteralPath $target).Length); issues: $($issues.Count)"
    Write-Output 'Originals retained. No training, locking, upload, or source modifications. Read manifest exclusions before claiming completeness.'
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
}
