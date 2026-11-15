param([switch]$PackageOnly)
# Frozen review only. Never retry, train, update Git, or change run locks/state.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root=Split-Path $PSScriptRoot -Parent
$bundle=Join-Path $root 'artifacts/packages/sac-child-history-20261116'
[IO.Directory]::CreateDirectory($bundle)|Out-Null
$launcher=[IO.File]::Open((Join-Path $bundle 'launcher.lock'),'OpenOrCreate','ReadWrite','None')
$lock=$null;$zip=$null;$failure=$null
try {
    if(-not $PackageOnly){
        try {
            $matlab=(Get-Command matlab.exe -ErrorAction Stop).Source
            $escaped=$root.Replace("'","''")
            & $matlab -wait -logfile (Join-Path $bundle 'matlab.log') -batch "cd('$escaped'); addpath(pwd); trainingtools.review_sac_child_history();"
            if($LASTEXITCODE -ne 0){$failure="MATLAB exit $LASTEXITCODE; see review.json and matlab.log."}
        }catch{$failure=$_.Exception.Message}
        [IO.File]::WriteAllText((Join-Path $bundle 'launcher_result.json'),(@{error=$failure;ended_at=(Get-Date).ToString('o')}|ConvertTo-Json))
    }
    $lock=[IO.File]::Open((Join-Path $bundle 'review.lock'),'OpenOrCreate','ReadWrite','None')
    $lines=@('# Child checkpoint frozen review','', 'No training or stage transition. These are previously inspected diagnostic routes, not an independent generalization claim.','')
    if(Test-Path (Join-Path $bundle 'review.json')){
        $state=Get-Content (Join-Path $bundle 'review.json') -Raw|ConvertFrom-Json
        $lines+="Status: $($state.status); completed: $($state.completed_episodes -join ', ')"
    }
    if(Test-Path (Join-Path $bundle 'summary.json')){
        $rows=Get-Content (Join-Path $bundle 'summary.json') -Raw|ConvertFrom-Json
        $lines+=@('','| Episode | Calm full / 10 | Weak full / 10 | Actual wind full / count | Calm mean steps | Weak mean steps |','|---|---|---|---|---|---|')
        foreach($r in $rows){$lines+="| $($r.episode) | $($r.full_counts[0]) | $($r.full_counts[1]) | $($r.actual_wind_full)/$($r.actual_wind_count) | $($r.mean_steps[0]) | $($r.mean_steps[1]) |"}
    }
    [IO.File]::WriteAllLines((Join-Path $bundle 'RESULTS.md'),$lines,[Text.UTF8Encoding]::new($false))
    $name='sac-child-history-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.zip'
    $target=Join-Path (Split-Path $bundle -Parent) $name;$pending=$target+'.partial'
    $files=New-Object 'System.Collections.Generic.List[object]'
    $stack=New-Object 'System.Collections.Generic.Stack[string]';$stack.Push($bundle)
    while($stack.Count){
        foreach($f in Get-ChildItem -LiteralPath $stack.Pop() -Force){
            if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Linked path refused: $($f.FullName)"}
            if($f.PSIsContainer){$stack.Push($f.FullName);continue}
            if($f.Extension -eq '.lock'){continue}
            $files.Add([pscustomobject]@{entry=$f.FullName.Substring($bundle.Length+1).Replace('\','/');source=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash})
        }
    }
    $zip=[IO.Compression.ZipFile]::Open($pending,[IO.Compression.ZipArchiveMode]::Create)
    $n=0
    foreach($f in $files){
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$f.source,$f.entry,[IO.Compression.CompressionLevel]::Optimal)|Out-Null
        $n++;if($n%25 -eq 0){Write-Output "Packing $n/$($files.Count) files"}
    }
    $writer=[IO.StreamWriter]::new($zip.CreateEntry('package_manifest.json').Open())
    try{$writer.Write((@{scope='Only this child frozen review; no training checkpoints';files=@($files.ToArray())}|ConvertTo-Json -Depth 6))}finally{$writer.Dispose()}
    $zip.Dispose();$zip=$null
    Write-Output 'Verifying ZIP payload hashes...'
    $zip=[IO.Compression.ZipFile]::OpenRead($pending)
    foreach($f in $files){
        $e=$zip.GetEntry($f.entry);if($null -eq $e -or $e.Length -ne $f.bytes){throw 'ZIP length mismatch'}
        $s=$e.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=[BitConverter]::ToString($sha.ComputeHash($s)).Replace('-','')}finally{$s.Dispose();$sha.Dispose()}
        if($actual -ne $f.sha256){throw "ZIP hash mismatch: $($f.entry)"}
    }
    $zip.Dispose();$zip=$null
    Move-Item -LiteralPath $pending -Destination $target
    $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    [IO.File]::WriteAllText(($target+'.sha256'),$hash+'  '+$name)
    Write-Output "Verified ZIP: $target";Write-Output "SHA256: $hash"
    if($failure){throw $failure}
}finally{if($null -ne $zip){$zip.Dispose()};if($null -ne $lock){$lock.Dispose()};$launcher.Dispose()}
