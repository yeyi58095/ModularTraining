$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Get-Content (Join-Path $root 'tests/output/sac-review-cycle-fixture-latest.json') -Raw | ConvertFrom-Json
$folder=[IO.Path]::GetFullPath([string]$fixture.folder)
$allowed=[IO.Path]::GetFullPath((Join-Path $root 'tests/output'))+'\'
if(-not $folder.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture outside tests/output'}
$tools=Join-Path $folder 'tools';[IO.Directory]::CreateDirectory($tools)|Out-Null
foreach($name in @('pack_sac_review_cycle.ps1','run_sac_review_cycle.ps1')){
    Copy-Item -LiteralPath (Join-Path $root "tools/$name") -Destination (Join-Path $tools $name)
}
$child=[string]$fixture.child
[IO.File]::WriteAllText((Join-Path $child 'supervisor.lock'),'')
& (Join-Path $tools 'run_sac_review_cycle.ps1') -PackageOnly
$zip=Get-ChildItem (Join-Path $folder 'artifacts/packages') -Filter '*.zip'|Sort-Object LastWriteTime|Select-Object -Last 1
if($null -eq $zip){throw 'Missing archive'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    $r=[IO.StreamReader]::new($z.GetEntry('manifest.json').Open());$m=$r.ReadToEnd()|ConvertFrom-Json;$r.Dispose()
    if(@($m.files|Where-Object {$_.entry -notmatch '^(cycle|child)/'}).Count){throw 'Unexpected payload scope'}
    if(-not $z.GetEntry('cycle/selection.json') -or -not $z.GetEntry('child/Agent_Final.mat')){throw 'Missing results'}
}finally{$z.Dispose()}
# An active child must be omitted, never copied or unlocked.
$lock=[IO.File]::Open((Join-Path $child 'supervisor.lock'),'Open','ReadWrite','None')
try { & (Join-Path $tools 'run_sac_review_cycle.ps1') -PackageOnly }finally{$lock.Dispose()}
$zip=Get-ChildItem (Join-Path $folder 'artifacts/packages') -Filter '*.zip'|Sort-Object LastWriteTime|Select-Object -Last 1
$z=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
try {
    $r=[IO.StreamReader]::new($z.GetEntry('manifest.json').Open());$m=$r.ReadToEnd()|ConvertFrom-Json;$r.Dispose()
    if(@($m.files|Where-Object {$_.entry -like 'child/*'}).Count -or $m.issues.Count -ne 1){throw 'Locked child exported'}
}finally{$z.Dispose()}
Write-Output 'PACK_REVIEW_TEST_OK: narrow payloads, ZIP verification, package-only and locked-child exclusion.'
