$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output/groups_'+[guid]::NewGuid().ToString('N'))
$group=Join-Path $fixture 'experiments/progressive_v2/groups/group_test'
$run=Join-Path $fixture 'experiments/progressive_v2/runs/run_test'
$null=New-Item -ItemType Directory -Path $group,$run
git init -q $fixture
if($LASTEXITCODE -ne 0){throw 'Fixture git init failed.'}
[IO.File]::WriteAllText((Join-Path $run 'control.json'),'source remains unchanged')
$before=(Get-FileHash (Join-Path $run 'control.json')).Hash
$catalog=@{schema_version=1;group_id='group_test';curriculum='progressive_v2';runs=@(@{id='run_test'},@{id='missing_run'})}
$catalog | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $group 'group.json')
$tool=Join-Path $root 'tools/link_experiment_groups.ps1'
& $tool -ProjectRoot $fixture
if(Test-Path (Join-Path $group 'runs')){throw 'Preview wrote shortcuts.'}
& $tool -ProjectRoot $fixture -Apply
$link=Join-Path $group 'runs/run_test.lnk'
if(-not(Test-Path $link)){throw 'Missing link.'}
if(Test-Path (Join-Path $group 'runs/missing_run.lnk')){throw 'Linked missing run.'}
$beforeLink=(Get-FileHash $link).Hash
& $tool -ProjectRoot $fixture -Apply
if((Get-FileHash $link).Hash -ne $beforeLink){throw 'Rewrote existing link.'}
if((Get-FileHash (Join-Path $run 'control.json')).Hash -ne $before){throw 'Run changed.'}
$shell=New-Object -ComObject WScript.Shell
try{
    $changed=$shell.CreateShortcut($link);$changed.Arguments='unexpected';$changed.Save()
}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
$changedHash=(Get-FileHash $link).Hash
$refused=$false
try{& $tool -ProjectRoot $fixture -Apply}catch{$refused=$true}
if(-not $refused -or (Get-FileHash $link).Hash -ne $changedHash){throw 'Foreign shortcut not preserved.'}
$catalog.runs=@(@{id='../escape'})
$catalog | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $group 'group.json')
$refused=$false
try{& $tool -ProjectRoot $fixture -Apply}catch{$refused=$true}
if(-not $refused){throw 'Traversal not rejected.'}
Write-Output 'PASS preview, folder shortcut target, missing source, idempotence, immutable run, foreign shortcut preservation and path traversal refusal.'
