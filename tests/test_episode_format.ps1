$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime/checkpoint_worker_diagnostics.ps1')
$folder = Join-Path $PSScriptRoot 'output'
$null = New-Item -ItemType Directory -Path $folder -Force
$log = Join-Path $folder 'episode-format.log'
$csv = Join-Path $folder 'episode-format.csv'
if (Test-Path -LiteralPath $csv) { Remove-Item -LiteralPath $csv }
[IO.File]::WriteAllText($log,"Episode:   1/  1 | Episode reward: 284.73 | Episode Q0: 0.00`nEpisode: 1001/2000 | Episode reward: 100 | Episode Q0: 1`n")
$seen = [Collections.Generic.HashSet[int]]::new()
Save-EpisodeWorkers $log $csv 1 6 4 $seen
Save-EpisodeWorkers $log $csv 1 6 4 $seen
$rows = @(Import-Csv -LiteralPath $csv)
if ($rows.Count -ne 2 -or ($rows.Episode -join ',') -ne '1,1001') { throw 'Padded episode parsing regression' }
Remove-Item -LiteralPath $log,$csv
Write-Output 'PASS: padded / unpadded episode formats and deduplication.'
