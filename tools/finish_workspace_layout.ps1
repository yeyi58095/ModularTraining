param(
    [Parameter(Mandatory=$true)][string]$SessionPath,
    [switch]$Apply
)
# Run after git pull. Never launch training or change a run snapshot.
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
$run=(Resolve-Path -LiteralPath $SessionPath).Path
if(-not $run.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Session must belong to this checkout.'
}
$state=Get-Content -LiteralPath (Join-Path $run 'status.json') -Raw | ConvertFrom-Json
if($state.state -notin @('paused','stopped','success','error')){throw 'Run is not stopped.'}
$lock=[IO.File]::Open((Join-Path $run 'supervisor.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    Push-Location -LiteralPath $root
    try{
        foreach($name in @('organize_workspace.ps1','compact_workspace.ps1','link_experiment_groups.ps1')){
            $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $name))
            if($Apply){$arguments+='-Apply'}
            & powershell.exe @arguments
            if($LASTEXITCODE -ne 0){throw "Layout tool failed: $name"}
        }
    }finally{Pop-Location}
}finally{$lock.Dispose()}
Write-Output "Layout complete (Apply=$Apply). Original run and checkpoints retained; training not started."
