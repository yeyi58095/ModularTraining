param([switch]$Apply, [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\','/')
if(-not (Test-Path -LiteralPath (Join-Path $root '.git'))){throw 'Expected a Git working directory.'}
# Only known loose diagnostic inputs. No recursion through runs or output.
$names=@('candidate_review_*.zip','exploration_pair_*.zip','recovery_review_*.zip',
 'regression_detail_*.zip','regression_models_*.zip','stage6_review_*.zip','stage8_latest300.json',
 'compare_training_checkpoints.m.backup_*')
$files=@()
foreach($pattern in $names){$files+=@(Get-ChildItem -LiteralPath $root -File -Filter $pattern)}
$screens=Join-Path $root '新增資料夾'
if(Test-Path -LiteralPath $screens){
 if((Get-Item -LiteralPath $screens).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked source directory refused.'}
 $files+=@(Get-ChildItem -LiteralPath $screens -File -Filter '*.png')
}
$base=Join-Path $root 'artifacts/incoming'
foreach($dir in @((Join-Path $root 'artifacts'),$base)){
 if((Test-Path -LiteralPath $dir) -and ((Get-Item -LiteralPath $dir).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked destination refused.'}
}
$batch=Join-Path $base ('cleanup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$rows=@()
foreach($f in $files){
 if($f.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked source file refused.'}
 $relative=$f.FullName.Substring($root.Length+1)
 $tracked=@(& git -C $root ls-files -- $relative)
 if($LASTEXITCODE -ne 0){throw 'Git tracking check failed.'}
 if($tracked.Count){Write-Warning "Tracked file retained: $relative";continue}
 $target=[IO.Path]::GetFullPath((Join-Path $batch $relative))
 if(-not $target.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escapes workspace.'}
 if(Test-Path -LiteralPath $target){throw "Destination already exists: $target"}
 $rows+= [pscustomobject]@{source=$relative;destination=$target.Substring($root.Length+1);sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash;bytes=$f.Length}
}
if(-not $rows.Count){Write-Output 'Nothing to organize.';exit 0}
$rows | Format-Table source,bytes
if(-not $Apply){Write-Output 'Preview only. Run with -Apply to move these files.';exit 0}
New-Item -ItemType Directory -Path $batch | Out-Null
ConvertTo-Json -InputObject @($rows) -Depth 4 | Set-Content -LiteralPath (Join-Path $batch 'manifest.json') -Encoding UTF8
foreach($r in $rows){
 $source=Join-Path $root $r.source;$target=Join-Path $root $r.destination
 if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $r.sha256){throw "Source changed: $source"}
 New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
 Move-Item -LiteralPath $source -Destination $target
 if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $r.sha256){throw "Verification failed: $target"}
}
Write-Output "Moved and SHA256 verified $($rows.Count) files. Manifest: $batch\manifest.json"
Write-Output 'Runs, checkpoints, tracked files and other untracked files were retained. Empty source folders are retained.'
