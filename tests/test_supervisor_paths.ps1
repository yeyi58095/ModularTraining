# Exercise path and lock rejection without launching MATLAB.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$runtime=Join-Path $root 'runtime'
$supervisor=Join-Path $runtime 'checkpoint_supervisor.ps1'
$fixture=Join-Path $PSScriptRoot ('output\supervisor_paths_' + [guid]::NewGuid().ToString('N'))
$session=Join-Path $fixture 'local'
$source=Join-Path $fixture 'old'
$null=New-Item -ItemType Directory -Path $session,$source -Force
$control=Join-Path $session 'control.json'
$diagnostics=Join-Path $session 'diagnostics'
$status=Join-Path $session 'status.json'
$sourceStatus=Join-Path $source 'status.json'
Set-Content -LiteralPath $sourceStatus -Value 'unchanged'
Set-Content -LiteralPath $status -Value 'unchanged'
$before=(Get-FileHash -LiteralPath $status).Hash
$sourceBefore=(Get-FileHash -LiteralPath $sourceStatus).Hash
$config=@{
    sessionDir=$session
    scriptDir=$runtime
    modularRoot=$root
    diagnosticDir=$diagnostics
    matlabExe=(Get-Process -Id $PID).Path
}
function Write-Control($value) {
    $value | ConvertTo-Json | Set-Content -LiteralPath $control -Encoding UTF8
}
function Assert-Rejected($value,[string]$expected) {
    Write-Control $value
    try { & $supervisor -ConfigFile $control } catch {
        if ($_.Exception.Message -notlike "*$expected*") { throw }
        return
    }
    throw "Expected rejection: $expected"
}

$stale=$config.Clone()
$stale.sessionDir=$source
Assert-Rejected $stale 'another run or checkout'
$stale=$config.Clone()
$stale.scriptDir=$source
Assert-Rejected $stale 'another run or checkout'
$stale=$config.Clone()
$otherDrive=if ([IO.Path]::GetPathRoot($root) -eq 'Z:\') { 'Y:\' } else { 'Z:\' }
$stale.diagnosticDir=[IO.Path]::Combine($otherDrive,'stale','diagnostics')
Assert-Rejected $stale 'outside the checkout volume'
$stale=$config.Clone()
$stale.resumeAgentFile=Join-Path $source 'Agent_Final.mat'
Assert-Rejected $stale 'checkpoint belongs to another run'
if ((Test-Path -LiteralPath (Join-Path $source 'supervisor.lock')) -or
    (Test-Path -LiteralPath (Join-Path $session 'supervisor.lock')) -or
    (Test-Path -LiteralPath $diagnostics) -or
    (Get-FileHash -LiteralPath $sourceStatus).Hash -ne $sourceBefore) {
    throw 'Path rejection modified a run.'
}

$lock=[IO.File]::Open((Join-Path $session 'supervisor.lock'),'OpenOrCreate','ReadWrite','None')
try {
    Write-Control $config
    $rejected=$false
    try { & $supervisor -ConfigFile $control } catch { $rejected=$true }
    if (-not $rejected) { throw 'Active lock was ignored.' }
    if ((Get-FileHash -LiteralPath $status).Hash -ne $before -or
        (Test-Path -LiteralPath (Join-Path $session 'supervisor.log'))) {
        throw 'A supervisor without the lock modified the active run.'
    }
} finally { $lock.Dispose() }

$null=New-Item -ItemType File -Path (Join-Path $session 'STOP')
& $supervisor -ConfigFile $control
$state=Get-Content -LiteralPath $status -Raw | ConvertFrom-Json
if ($state.state -ne 'stopped' -or -not (Test-Path -LiteralPath $diagnostics) -or
    (Get-ChildItem -LiteralPath $session -Directory -Filter 'attempt_*')) {
    throw 'Valid local control should reach STOP without launching an attempt.'
}
Write-Output 'PASS portable supervisor paths, exclusive lock and local STOP.'
