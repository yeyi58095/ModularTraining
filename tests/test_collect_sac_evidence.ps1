$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$collector=Join-Path $root 'tools/collect_sac_evidence.ps1'
$fixture=Join-Path $root ('tests/output/sac-evidence-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
function Put([string]$rel,[string]$text) {
    $p=Join-Path $fixture $rel
    $null=New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
    [IO.File]::WriteAllText($p,$text,(New-Object Text.UTF8Encoding($false)))
}
function Assert($condition,[string]$message) { if (-not $condition) { throw $message } }
Put 'experiments/sac/runs/parent/model.json' '{"name":"sac_lstm128","algorithm":"SAC"}'
Put 'experiments/sac/runs/parent/status.json' '{"state":"paused"}'
Put 'experiments/sac/runs/parent/attempt_00001/stdout.log' 'Episode: 1/500 | historical evidence'
Put 'experiments/sac/runs/parent/attempt_00001/stderr.log' ''
Put 'experiments/sac/runs/parent/supervisor.lock' 'preserved lock bytes'
Put 'experiments/sac/runs/parent/checkpoints/Agent1000.mat' 'fake checkpoint, never load'
Put 'experiments/sac/runs/parent/reports/evaluation_test/ep1000_stage1_seed101.mat' 'fake trace, never load'
Put 'experiments/sac/runs/parent/reports/evaluation_test/evaluation.json' '{"status":"complete"}'
Put 'experiments/sac/runs/parent/slprj/generated.txt' 'cache must be skipped'
Put 'experiments/sac/runs/parent/attempt_00001/large.txt' ('X'*2048)
Put 'experiments/mlp/runs/child/model.json' '{"name":"sac_mlp128","algorithm":"SAC"}'
Put 'experiments/mlp/runs/child/status.json' '{"state":"running"}'
Put 'experiments/mlp/runs/child/recovery.json' '{"parent_session":"D:\\old-machine\\project\\experiments\\sac\\runs\\parent","parent_episode":1000}'
Put 'experiments/mlp/runs/child/attempt_00002/stdout.log' 'another branch'
Put 'experiments/ppo/runs/other/model.json' '{"name":"ppo_lstm128","algorithm":"PPO"}'
Put 'experiments/ppo/runs/other/attempt_00001/stdout.log' 'PPO must not be exported'
Put 'sessions/broken/model.json' 'invalid JSON'
Put 'artifacts/sac-run.txt' 'a portable receipt'
Put 'artifacts/incoming/sac-old/evaluation.json' '{"status":"complete"}'
Put 'artifacts/incoming/sac-old/source.zip' 'old archive should be inventoried, not nested by default'

$before=@{}
foreach ($f in Get-ChildItem -LiteralPath $fixture -Recurse -File) { $before[$f.FullName]=(Get-FileHash -LiteralPath $f.FullName).Hash }
$preview=& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ProjectRoot $fixture -Preview 2>&1
Assert ($LASTEXITCODE -eq 0) "Preview failed: $preview"
Assert (-not (Test-Path (Join-Path $fixture 'artifacts/packages'))) 'Preview created output'
$result=& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ProjectRoot $fixture -IncludeEvaluationTraces -MaxFileMB .001 2>&1
Assert ($LASTEXITCODE -eq 0) "Collection failed: $result"
$packages=@(Get-ChildItem (Join-Path $fixture 'artifacts/packages/sac-evidence') -Filter '*.zip')
Assert ($packages.Count -eq 1) 'Expected one verified package'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($packages[0].FullName)
try {
    $reader=New-Object IO.StreamReader($zip.GetEntry('manifest.json').Open())
    try { $manifest=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    Assert ($manifest.runs.Count -eq 2) 'SAC discovery included PPO or lost child'
    Assert (@($manifest.runs | Where-Object state_at_discovery -eq 'running').Count -eq 1) 'Active state not recorded'
    Assert (@($manifest.issues | Where-Object reason -eq 'parent_missing_or_ambiguous').Count -eq 0) 'Relocated parent ID resolution failed'
    Assert (@($manifest.issues | Where-Object reason -eq 'unreadable_json').Count -eq 1) 'Malformed model not reported'
    Assert ($null -ne $zip.GetEntry('evidence/experiments/sac/runs/parent/attempt_00001/stdout.log')) 'Attempt log missing'
    Assert ($null -ne $zip.GetEntry('evidence/experiments/mlp/runs/child/attempt_00002/stdout.log')) 'Child attempt missing'
    Assert ($null -ne $zip.GetEntry('evidence/experiments/sac/runs/parent/reports/evaluation_test/ep1000_stage1_seed101.mat')) 'Requested trace missing'
    Assert ($null -eq $zip.GetEntry('evidence/experiments/sac/runs/parent/checkpoints/Agent1000.mat')) 'Checkpoint accidentally included'
    Assert (@($manifest.files | Where-Object exclusion_reason -eq 'lock_file_not_copied').Count -eq 1) 'Lock exclusion missing'
    Assert (@($manifest.files | Where-Object exclusion_reason -eq 'over_MaxFileMB').Count -eq 1) 'Size exclusion missing'
    foreach ($f in @($manifest.files | Where-Object included)) {
        $entry=$zip.GetEntry('evidence/'+$f.path)
        $s=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($sha.ComputeHash($s)).Replace('-','').ToLowerInvariant() }
        finally { $s.Dispose();$sha.Dispose() }
        Assert ($hash -eq $f.sha256) "Payload hash mismatch: $($f.path)"
    }
} finally { $zip.Dispose() }
foreach ($p in $before.Keys) { Assert ((Get-FileHash -LiteralPath $p).Hash -eq $before[$p]) "Source changed: $p" }
Assert (-not (Test-Path (Join-Path $fixture 'experiments/mlp/runs/child/supervisor.lock'))) 'Collector created a run lock'
# Repeat collection publishes a distinct package, never overwriting the first.
$again=& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ProjectRoot $fixture -IncludeCheckpoints -MaxFileMB .001 2>&1
Assert ($LASTEXITCODE -eq 0) "Second collection failed: $again"
Assert (@(Get-ChildItem (Join-Path $fixture 'artifacts/packages/sac-evidence') -Filter '*.zip').Count -eq 2) 'Repeat overwrote archive'
$second=@(Get-ChildItem (Join-Path $fixture 'artifacts/packages/sac-evidence') -Filter '*.zip' | Where-Object FullName -ne $packages[0].FullName)[0]
$zip=[IO.Compression.ZipFile]::OpenRead($second.FullName)
try {
    Assert ($null -ne $zip.GetEntry('evidence/experiments/sac/runs/parent/checkpoints/Agent1000.mat')) 'Checkpoint opt-in did not work'
} finally { $zip.Dispose() }
# A synthetic concurrent writer verifies that a growing active stdout is bounded
# and marked, without starting MATLAB or touching a real training run.
$growing=Join-Path $fixture 'experiments/mlp/runs/child/growing.log'
$s=[IO.File]::Open($growing,'CreateNew','Write','ReadWrite')
try { $s.SetLength(32MB) } finally { $s.Dispose() }
$packageDir=Join-Path $fixture 'artifacts/packages/sac-evidence'
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
public static class SacEvidenceTestWriter {
    public static Task Start(string log, string destination) {
        return Task.Run(() => {
            var deadline=DateTime.UtcNow.AddSeconds(30);
            while (Directory.GetFiles(destination, "*.partial").Length==0) {
                if (DateTime.UtcNow>deadline) throw new Exception("No partial export observed");
                Thread.Sleep(5);
            }
            using(var h=new FileStream(log,FileMode.Append,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)) {
                while(Directory.GetFiles(destination,"*.partial").Length>0 && DateTime.UtcNow<deadline) {
                    h.WriteByte(65);h.Flush();Thread.Sleep(2);
                }
            }
        });
    }
}
"@
$writer=[SacEvidenceTestWriter]::Start($growing,$packageDir)
try {
    $live=& powershell -NoProfile -ExecutionPolicy Bypass -File $collector -ProjectRoot $fixture -MaxFileMB 0 2>&1
    Assert ($LASTEXITCODE -eq 0) "Live collection failed: $live"
    $null=$writer.Wait(10000)
    $liveManifest=Get-ChildItem -LiteralPath $packageDir -Filter '*.manifest.json' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    $liveData=Get-Content -LiteralPath $liveManifest.FullName -Raw | ConvertFrom-Json
    $g=@($liveData.files | Where-Object path -eq 'experiments/mlp/runs/child/growing.log')[0]
    Assert $g.changed_during_copy 'Concurrent append was not detected'
    Assert ($g.bytes_exported -lt (Get-Item -LiteralPath $growing).Length) 'Live read was not bounded to its starting size'
} finally { if (-not $writer.IsCompleted) { $null=$writer.Wait(30000) } }
Write-Output "PASS: SAC discovery, relocated lineage, all attempts, live append bounded/detected, trace/checkpoint opt-in, exclusions, ZIP hashes, source/lock preservation, repeat export. Fixture: $fixture"
