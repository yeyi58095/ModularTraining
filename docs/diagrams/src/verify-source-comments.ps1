# 靜態驗證：忽略新增註解後，PowerShell token／AST 應與修改前一致。
param([string]$BaselinePath = (Join-Path $PSScriptRoot '../../../tests/output/code-comments-baseline.json'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$baseline=Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
$count=0
foreach ($entry in $baseline.PSObject.Properties) {
    if (-not $entry.Name.EndsWith('.ps1')) { continue }
    $original=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($entry.Value.originalBase64))
    $current=[IO.File]::ReadAllText((Join-Path $root $entry.Name))
    $oldTokens=$null; $oldErrors=$null; $newTokens=$null; $newErrors=$null
    $oldAst=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$oldTokens,[ref]$oldErrors)
    $newAst=[Management.Automation.Language.Parser]::ParseInput($current,[ref]$newTokens,[ref]$newErrors)
    if ($newErrors.Count -ne 0) { throw "PowerShell parse failure: $($entry.Name): $newErrors" }
    $oldCode=@($oldTokens | Where-Object { $_.Kind -notin @('Comment','NewLine','EndOfInput') } | ForEach-Object { "$($_.Kind):$($_.Text)" })
    $newCode=@($newTokens | Where-Object { $_.Kind -notin @('Comment','NewLine','EndOfInput') } | ForEach-Object { "$($_.Kind):$($_.Text)" })
    if (($oldCode | ConvertTo-Json -Compress) -cne ($newCode | ConvertTo-Json -Compress)) { throw "PowerShell executable tokens changed: $($entry.Name)" }
    $oldKinds=@($oldAst.FindAll({param($node) $true},$true) | ForEach-Object { $_.GetType().FullName })
    $newKinds=@($newAst.FindAll({param($node) $true},$true) | ForEach-Object { $_.GetType().FullName })
    if (($oldKinds | ConvertTo-Json -Compress) -cne ($newKinds | ConvertTo-Json -Compress)) { throw "PowerShell AST changed: $($entry.Name)" }
    $count++
}
Write-Output "PASS: $count PowerShell files parse with identical executable tokens and AST structure. No scripts executed."
