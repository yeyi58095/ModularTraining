# MLP SAC long continuation from Agent1000

## Source evidence and decision

The supplied `training_status(sacDir,50)` identifies run `20261026_184028_tpcff39fc6_3ef5_4435_bfaa_cfffd7ebc83f`, paused normally after attempt 2. Saved progress is Episode1000/2000. Recent 100-episode conditions remain far below the original gate: reward mean158.94/1200, steps mean263.64/2700, full-length rate0%/80%. The supplied stdout ends at Episode1000, reports normal save, and has no success. This does not establish that the MLP has converged or that another segment will improve it.

The original run remains unchanged. `sac_mlp_100k_continuous.json` prepares a child from Agent1000 with source lineage, weights, SAC optimizer and replay preserved. Actor learning rate and replay capacity remain unchanged. The child snapshots the source environment and course; only `on_limit` becomes `continue`, as required for explicit continuous mode. Original reward, step and full-length success conditions remain. Guard budget pausing is disabled and regressions are monitored. The child stops on the original course success, after 200 supervisor attempts of 500 episodes (maximum 100,000 additional episodes), a runtime failure, or a user STOP request.

Each process saves every100 episodes. The supervisor's `STOP` request force-terminates the active MATLAB process; checkpoints already saved remain intact, but up to99 unsaved episodes may be lost. The project does not implement a graceful mid-process stop. No local or remote training was started by preparing this recipe. SAC continuous recovery was explicitly rejected by the previous helper, so the helper now allows it only when no exploration scaling is requested; no existing run snapshot or runtime engine behavior is changed.

## Remote preparation and start

Run only after syncing this change to the remote project and confirming all other runs are paused. In MATLAB:

```matlab
cd('D:\daniel\ModularTraining');
clear functions;
sacDir=string(strtrim(fileread(fullfile(pwd,'artifacts','sac-mlp-stage1-run.txt'))));
parentStatus=jsondecode(fileread(fullfile(sacDir,'status.json')));
assert(strcmp(parentStatus.state,'paused'),'Parent MLP run must be paused.');
info=trainingtools.prepare_recovery_training(sacDir,"configs/sac_mlp_100k_continuous.json");
longDir=string(info.sessionDir);
writelines(longDir,fullfile(pwd,'artifacts','sac-mlp-continuous-100k-run.txt'));
training_status(longDir,50);
retry(resume=longDir,maxAttempts=200,episodesPerProcess=500, ...
    checkpointEvery=100,executionMode='serial',device='cpu',fastRestart='off');
```

Preparation acquires the parent run's exclusive lock and validates the selected saved checkpoint. It creates a separate paused child and does not launch it. Inspect the child path, source episode, lineage SHA and snapshots before the explicit `retry` start. Do not run another training copy at the same time.

Monitor in MATLAB with:

```matlab
training_status(longDir,50);
```

For a manual stop, create an empty `STOP` file in the child session folder. This force-stops the active MATLAB segment; use only when willing to discard work since the last100-episode checkpoint. The parent run remains paused and unchanged.

## Evidence archive

The pasted status and `mlp_stdout.log` are archived in `artifacts/incoming/sac-mlp-continuation-review-20261026/`.

- `mlp_stdout.log`, original `D:\daniel\GradSchool\0-Beginner\ModularTraining\mlp_stdout.log`, SHA256 `0103644947404F2BC9E9B83D164B4EE1750C1E1088991C78326F9964E40FE45C`.
- `training_status.txt`, copied from `C:\Users\yeyi5\.codex\attachments\bc1a6269-91f1-45a5-95d7-0024b7f536a0\貼上的文字.txt`, SHA256 `82127D7C29F99331C9E60D9E96A053A51A1A72FEEB03C5ABE6D3A6EF5EC4F341`.

Verification in this workspace is static review only. The remote preparation and training command have not been executed, and this long SAC continuation path has not been runtime-tested. Training remains user-executed.
