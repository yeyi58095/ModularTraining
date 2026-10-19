param([switch]$Apply, [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
# Only local presentation intermediates and root Python cache. Never visit runs.
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\','/')
if(-not(Test-Path -LiteralPath (Join-Path $root '.git'))){throw 'Expected Git workspace.'}
function Safe-Path([string]$relative) {
    $full=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside workspace.'}
    $part=$full
    while($part -and $part.Length -ge $root.Length){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -Force -LiteralPath $part).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked path refused: $part"}
        $part=Split-Path $part -Parent
    }
    return $full
}
$batch='artifacts/incoming/layout-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$moves=@(
    @{source='.meeting-build';destination='output/meeting_training_20261014/build'},
    @{source='__pycache__';destination="$batch/root-python-cache"}
)
$rows=@();$active=@()
foreach($move in $moves){
    $source=Safe-Path $move.source; $target=Safe-Path $move.destination
    if(-not(Test-Path -LiteralPath $source)){continue}
    if(Test-Path -LiteralPath $target){throw "Destination exists; inspect before retry: $target"}
    # Check links before traversing each directory, never recurse into junctions.
    $queue=[Collections.Generic.Queue[string]]::new();$queue.Enqueue($source)
    while($queue.Count){
        foreach($item in Get-ChildItem -Force -LiteralPath $queue.Dequeue()){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Linked item refused: $($item.FullName)"}
            if($item.PSIsContainer){$queue.Enqueue($item.FullName);continue}
            $relative=$item.FullName.Substring($root.Length+1)
            $tracked=@(& git -C $root ls-files -- $relative)
            if($LASTEXITCODE -ne 0){throw 'Git tracking check failed.'}
            if($tracked.Count){throw "Tracked file retained; cannot move group: $relative"}
            $suffix=$item.FullName.Substring($source.Length+1)
            $rows += [pscustomobject]@{source=$relative;destination=(Join-Path $move.destination $suffix);sha256=(Get-FileHash -LiteralPath $item.FullName).Hash;bytes=$item.Length}
        }
    }
    $active += $move
}
if(-not $active.Count){Write-Output 'Nothing to compact.';exit 0}
$active | ForEach-Object {Write-Output "$($_.source) -> $($_.destination)"}
Write-Output "$($rows.Count) files; original bytes retained and verified."
if(-not $Apply){Write-Output 'Preview only. Use -Apply after inspection.';exit 0}
$receipt=Safe-Path $batch
$null=New-Item -ItemType Directory -Path $receipt -Force
ConvertTo-Json -InputObject @($rows) -Depth 5 | Set-Content -LiteralPath (Join-Path $receipt 'manifest.json') -Encoding UTF8
foreach($move in $active){
    $source=Safe-Path $move.source;$target=Safe-Path $move.destination
    foreach($row in $rows | Where-Object {$_.source.StartsWith($move.source+[IO.Path]::DirectorySeparatorChar)}){
        if((Get-FileHash -LiteralPath (Safe-Path $row.source)).Hash -ne $row.sha256){throw 'Source changed during move.'}
    }
    $null=New-Item -ItemType Directory -Path (Split-Path $target) -Force
    Move-Item -LiteralPath $source -Destination $target
}
foreach($row in $rows){
    if((Get-FileHash -LiteralPath (Safe-Path $row.destination)).Hash -ne $row.sha256){throw "Destination mismatch: $($row.destination)"}
}
$edits=@()
foreach($row in $rows | Where-Object {$_.source.StartsWith('.meeting-build'+[IO.Path]::DirectorySeparatorChar) -and $_.source -match '\.(py|mjs)$'}){
    $file=Safe-Path $row.destination
    $original=[IO.File]::ReadAllText($file)
    $updated=$original.Replace('.meeting-build','output/meeting_training_20261014/build')
    $updated=$updated.Replace("Path(__file__).resolve().parent.parent/'output/", "Path(__file__).resolve().parents[3]/'output/")
    if($updated -ne $original){
        $backup=Join-Path $receipt ('original-scripts/'+[IO.Path]::GetFileName($file))
        $null=New-Item -ItemType Directory -Path (Split-Path $backup) -Force
        Copy-Item -LiteralPath $file -Destination $backup
        [IO.File]::WriteAllText($file,$updated,[Text.UTF8Encoding]::new($false))
        $edits += [pscustomobject]@{file=$row.destination;original_sha256=$row.sha256;updated_sha256=(Get-FileHash -LiteralPath $file).Hash;original_copy=$backup.Substring($root.Length+1)}
    }
}
ConvertTo-Json -InputObject @($edits) -Depth 5 | Set-Content -LiteralPath (Join-Path $receipt 'script-path-updates.json') -Encoding UTF8
Write-Output "Verified. Receipt: $receipt/manifest.json; script-path-updates.json records subsequent path edits."
Write-Output 'Original build scripts preserved in receipt; relocated references updated. No deck rebuilt.'
