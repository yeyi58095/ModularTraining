param([switch]$Start)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$bundle=Join-Path $root 'artifacts/packages/sac-fresh-schedule-20261121'
$local=Join-Path $bundle 'runtime-local'
$batch=Join-Path $local 'batch'
$temp=Join-Path $local 'temp'
[IO.Directory]::CreateDirectory($batch)|Out-Null
[IO.Directory]::CreateDirectory($temp)|Out-Null
$mode=if($Start){'run'}else{'prepare'}
$matlab=(Get-Command matlab.exe -ErrorAction Stop).Source
$escaped=$root.Replace("'","''")
$log=Join-Path $bundle ('matlab-'+$mode+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.log')
$previousTemp=$env:TEMP
$previousTmp=$env:TMP
Push-Location -LiteralPath $batch
try {
    $env:TEMP=$temp
    $env:TMP=$temp
    & $matlab -wait -logfile $log -batch "addpath('$escaped','-begin'); trainingtools.run_sac_fresh_schedule('$mode');"
    exit $LASTEXITCODE
} finally {
    $env:TEMP=$previousTemp
    $env:TMP=$previousTmp
    Pop-Location
}
