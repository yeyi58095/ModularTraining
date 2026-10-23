# Prepare SAC replay-capacity comparison

2026-10-23 correction: the previous replay comparison falsely rejected wrapped full buffers because physical ring-slot order changes on growth. The updated helper verifies chronological records and tracker IDs. The remote baseline20261022_132700_recovery_tp4c73786a from the failed preparation remains untouched; rerun once to prepare a new complete pair after pulling this fix. Do not start the old baseline or delete parent locks.

This step prepares only, with no remote training launched. Parent must remain paused. Both children start at saved Agent1100, inherit course/environment/model source, and record parent SHA/episode. Baseline retains100000 replay capacity; candidate uses500000. Existing replay data are retained; older overwritten data cannot be recovered.

R2024b's ordinary SAC AgentOptions setter can reset learning state. The helper reconstructs the serialized agent, cloning and growing replay while checking actor/twin critic/target weights, optimizer states, entropy policy state and replay contents. Support is deliberately restricted to R2024b and unchanged learning rates/exploration. No PPO-to-SAC conversion.

Both children are prepared with STOP present, serial CPU,500 episodes/attempt, maxAttempts1, and a recovery budget of1000 additional episodes. The original course gates remain. Existing parent guard thresholds are inherited when present; otherwise the established recovery guard uses100-episode windows, patience3, reward/steps ratio0.5 and reference minima500. Preparation does not establish equal environment-step training budgets: differing episode lengths must be accounted for before any comparative claim. Do not launch either child until the preparation receipt has been reviewed; do not run both concurrently.

Remote PowerShell, while original run is paused:

```powershell
$ErrorActionPreference = 'Stop'
cd D:\daniel\ModularTraining
$session = (Get-Content '.\artifacts\sac-serial-500-run.txt' -Raw).Trim()
$s = Get-Content (Join-Path $session 'status.json') -Raw | ConvertFrom-Json
if ($s.state -ne 'paused') { throw 'Parent must remain paused.' }
$lock = [IO.File]::Open((Join-Path $session 'supervisor.lock'), 'Open', 'ReadWrite', 'None')
$lock.Dispose()
git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) { throw 'Git sync failed; do not continue.' }
```

Fresh MATLAB, once:

```matlab
cd('D:\daniel\ModularTraining');
sacDir = string(strtrim(fileread(fullfile(pwd,'artifacts','sac-serial-500-run.txt'))));
[~,name] = fileparts(sacDir);
assert(name == "20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b");
pair = trainingtools.prepare_sac_replay_pair(sacDir,1100);
copyfile(pair.receipt,fullfile(pwd,'artifacts','sac-replay-pair-latest.json'));
fprintf('Prepared only. Receipt: %s\n',fullfile(pwd,'artifacts','sac-replay-pair-latest.json'));
```

Return the displayed receipt or copy sac-replay-pair-latest.json into the local project root for intake. An interrupted preparation may leave a labelled .preparing directory; do not retry-launch it or delete parent locks. Re-running the preparation creates new children rather than overwriting existing ones.
