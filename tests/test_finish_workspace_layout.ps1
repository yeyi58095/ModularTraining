$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $root ('tests/output/layout_finish_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'status.json'),'{"state":"running"}')
[IO.File]::WriteAllText((Join-Path $fixture 'supervisor.lock'),'')
$tool=Join-Path $root 'tools/finish_workspace_layout.ps1'
$rejected=$false
try{& $tool -SessionPath $fixture}catch{$rejected=$true}
if(-not $rejected){throw 'Active run accepted.'}
[IO.File]::WriteAllText((Join-Path $fixture 'status.json'),'{"state":"paused"}')
$lock=[IO.File]::Open((Join-Path $fixture 'supervisor.lock'),'Open','ReadWrite','None')
try{
    $rejected=$false
    try{& $tool -SessionPath $fixture}catch{$rejected=$true}
    if(-not $rejected){throw 'Busy lock accepted.'}
}finally{$lock.Dispose()}
$before=(Get-FileHash -LiteralPath (Join-Path $fixture 'status.json')).Hash
& $tool -SessionPath $fixture
if((Get-FileHash -LiteralPath (Join-Path $fixture 'status.json')).Hash -ne $before){throw 'State changed.'}
Write-Output 'PASS active/busy refusal and read-only layout preview.'
