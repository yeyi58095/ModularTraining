$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output/env-preserve-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$runtime=Join-Path $fixture 'runtime';$null=New-Item -ItemType Directory -Path $runtime
[IO.File]::WriteAllText((Join-Path $runtime 'FAFA_Simulation.slx'),'synthetic model bytes')
[IO.File]::WriteAllText((Join-Path $runtime 'dependency.mat'),'synthetic asset bytes')
$hash=(Get-FileHash -LiteralPath (Join-Path $runtime 'FAFA_Simulation.slx')).Hash
$script=Join-Path $project 'tools/preserve_training_environment.ps1'
function New-Case([string]$name,[string]$state='paused') {
    $dir=Join-Path $fixture $name;$null=New-Item -ItemType Directory -Path $dir
    [IO.File]::WriteAllText((Join-Path $dir 'supervisor.lock'),'')
    [IO.File]::WriteAllText((Join-Path $dir 'status.json'),(@{state=$state}|ConvertTo-Json))
    [IO.File]::WriteAllText((Join-Path $dir 'control.json'),(@{scriptDir=$runtime}|ConvertTo-Json))
    foreach($n in @('checkpoint.mat','curriculum_state.json','training_guard_state.json','STOP')) {
        [IO.File]::WriteAllText((Join-Path $dir $n),'unchanged')
    }
    return $dir
}
function Reject([scriptblock]$action) {
    $failed=$false;try { & $action } catch {$failed=$true}
    if(-not $failed){throw 'Expected refusal.'}
}
$run=New-Case 'ok'
$before=@{};Get-ChildItem -LiteralPath $run -File|ForEach-Object {$before[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash}
& $script -SessionDir $run -ExpectedModelSha256 $hash
& $script -SessionDir $run -ExpectedModelSha256 $hash
foreach($n in $before.Keys) {if((Get-FileHash -LiteralPath (Join-Path $run $n)).Hash -ne $before[$n]) {throw "Source changed: $n"}}
if((Get-FileHash -LiteralPath (Join-Path $run 'environment/dependency.mat')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $runtime 'dependency.mat')).Hash){throw 'Dependency not preserved.'}
$active=New-Case 'active' 'running';Reject {& $script -SessionDir $active -ExpectedModelSha256 $hash}
$locked=New-Case 'locked';$handle=[IO.File]::Open((Join-Path $locked 'supervisor.lock'),'Open','ReadWrite','None')
try {Reject {& $script -SessionDir $locked -ExpectedModelSha256 $hash}} finally {$handle.Dispose()}
$wrong=New-Case 'wrong';Reject {& $script -SessionDir $wrong -ExpectedModelSha256 ('0'*64)}
if(Test-Path -LiteralPath (Join-Path $wrong 'environment')){throw 'Wrong hash created snapshot.'}
$traversal=New-Case 'traversal';Reject {& $script -SessionDir $traversal -ExpectedModelSha256 $hash -AdditionalFiles '../outside.m'}
[IO.File]::AppendAllText((Join-Path $run 'environment/FAFA_Simulation.slx'),'tamper')
Reject {& $script -SessionDir $run -ExpectedModelSha256 $hash}
Write-Output 'PASS remote preserve: hashes, dependencies, idempotence, stopped state, lock, traversal, tamper and source immutability.'
