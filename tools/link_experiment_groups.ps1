param([switch]$Apply, [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent))
# Local folder shortcuts only. No run mutation, junctions, or training.
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\','/')
if(-not(Test-Path -LiteralPath (Join-Path $root '.git'))){throw 'Expected Git workspace.'}
function Safe-Path([string]$relative){
    $full=[IO.Path]::GetFullPath((Join-Path $root $relative))
    if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Outside workspace.'}
    $part=$full
    while($part -and $part.Length -ge $root.Length){
        if((Test-Path -LiteralPath $part) -and ((Get-Item -Force -LiteralPath $part).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked path refused: $part"}
        $part=Split-Path $part -Parent
    }
    return $full
}
function Valid-Name($value){
    return ($value -is [string] -and $value -cmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,170}$' -and $value -notmatch '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$')
}
$catalog=Safe-Path 'experiments/progressive_v2/groups'
$entries=@();$seen=@{}
foreach($group in Get-ChildItem -LiteralPath $catalog -Directory){
    $groupPath=Safe-Path ('experiments/progressive_v2/groups/'+$group.Name)
    $file=Join-Path $groupPath 'group.json'
    if(-not(Test-Path -LiteralPath $file)){continue}
    $null=Safe-Path ('experiments/progressive_v2/groups/'+$group.Name+'/group.json')
    $meta=Get-Content -Raw -LiteralPath $file | ConvertFrom-Json
    if($meta.schema_version -ne 1 -or $meta.curriculum -ne 'progressive_v2' -or $meta.group_id -cne $group.Name -or -not(Valid-Name $meta.group_id)){throw "Invalid group: $file"}
    foreach($run in @($meta.runs)){
        if(-not(Valid-Name $run.id)){throw "Invalid run ID in $file"}
        if($seen.ContainsKey($run.id)){throw "Run assigned more than once: $($run.id)"};$seen[$run.id]=$true
        $target=Safe-Path ('experiments/progressive_v2/runs/'+$run.id)
        $shortcut=Safe-Path ('experiments/progressive_v2/groups/'+$group.Name+'/runs/'+$run.id+'.lnk')
        if(-not(Test-Path -LiteralPath $target -PathType Container)){Write-Output "Missing (no shortcut): $($group.Name) / $($run.id)";continue}
        $entries += [pscustomobject]@{group=$group.Name;target=$target;shortcut=$shortcut}
    }
}
$entries | ForEach-Object {Write-Output "$($_.group)/runs -> $($_.target)"}
if(-not $Apply){Write-Output 'Preview only. Use -Apply to create local folder shortcuts.';exit 0}
if(-not $entries.Count){Write-Output 'No local runs to link.';exit 0}
$shell=New-Object -ComObject WScript.Shell
try{
    # Validate all existing shortcuts before writing any new ones.
    foreach($entry in $entries){
        if(Test-Path -LiteralPath $entry.shortcut){
            $existing=$shell.CreateShortcut($entry.shortcut)
            if($existing.TargetPath -ine $entry.target -or $existing.Arguments){throw "Different shortcut retained: $($entry.shortcut)"}
        }
    }
    foreach($entry in $entries){
        if(Test-Path -LiteralPath $entry.shortcut){Write-Output "Already linked: $($entry.shortcut)";continue}
        $null=New-Item -ItemType Directory -Path (Split-Path $entry.shortcut) -Force
        $link=$shell.CreateShortcut($entry.shortcut)
        $link.TargetPath=$entry.target;$link.WorkingDirectory=$entry.target
        $link.Description='Original run folder; no copied training data.';$link.Save()
        $check=$shell.CreateShortcut($entry.shortcut)
        if($check.TargetPath -ine $entry.target){throw 'Shortcut verification failed.'}
        Write-Output "Linked: $($entry.shortcut)"
    }
}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
