$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('output/compact_'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path "$fixture/.meeting-build","$fixture/__pycache__"
git init -q $fixture
if($LASTEXITCODE -ne 0){throw 'Fixture git init failed.'}
[IO.File]::WriteAllText("$fixture/.meeting-build/build.py","from pathlib import Path`nroot=Path(__file__).resolve().parent.parent/'output/example'`nprint('.meeting-build/draft.pptx')")
[IO.File]::WriteAllText("$fixture/.meeting-build/draft.pptx",'synthetic deck bytes')
[IO.File]::WriteAllText("$fixture/__pycache__/sample.pyc",'cache')
$before=(Get-FileHash "$fixture/.meeting-build/draft.pptx").Hash
$tool=Join-Path $root 'tools/compact_workspace.ps1'
& $tool -ProjectRoot $fixture
if(-not(Test-Path "$fixture/.meeting-build/draft.pptx")){throw 'Preview moved files.'}
& $tool -ProjectRoot $fixture -Apply
if(Test-Path "$fixture/.meeting-build"){throw 'Source not moved.'}
if((Get-FileHash "$fixture/output/meeting_training_20261014/build/draft.pptx").Hash -ne $before){throw 'Deck changed.'}
$script=Get-Content -Raw "$fixture/output/meeting_training_20261014/build/build.py"
if($script -notmatch 'parents\[3\]' -or $script -match '\.meeting-build'){throw 'Script path not adapted.'}
$receipt=Get-ChildItem "$fixture/artifacts/incoming" -Directory | Select-Object -First 1
if(-not(Test-Path "$($receipt.FullName)/original-scripts/build.py")){throw 'Original script missing.'}
& $tool -ProjectRoot $fixture -Apply
$null=New-Item -ItemType Directory -Path "$fixture/.meeting-build"
$refused=$false
try { & $tool -ProjectRoot $fixture -Apply } catch { $refused=$true }
if(-not $refused){throw 'Existing destination not refused.'}
Write-Output 'PASS preview, immutable deck, script backup/path adaptation, cache archive, rerun and collision refusal.'
