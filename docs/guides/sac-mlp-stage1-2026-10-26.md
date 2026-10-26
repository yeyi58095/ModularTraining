# Fresh feedforward SAC Stage1 pilot

## Purpose and boundaries

The recurrent SAC runs repeatedly recovered and regressed. Neither increasing replay capacity nor lowering actor LR established stable training. This pilot asks whether a feedforward SAC baseline can learn and retain the original straight/calm task without recurrent-state/sequence-replay machinery. It does not assert that LSTM caused the old failures, that current observations are fully Markov, or that MLP will be better. Removing memory may hurt if the observation omits necessary state.

New profile sac_mlp128 uses the R2024b default SAC factory with UseRNN=false and NumHiddenUnit128. Gaussian actor squashing remains agent-managed, with twin critics. lstmUnits0 and SequenceLength1 replace128 and32. Other numerical settings match the original fresh recurrent profile: actor5e-5, critic1e-4, entropy1e-4/target-1/initial0.1, gamma0.98, batch64, replay100k, warmup1000, LearningFrequency32, one minibatch/epoch, tau0.005. Network topology/parameter count and number of sampled transition positions per update necessarily differ; this is not an equal-compute isolated LSTM causality test. No claimed speedup or standard optimal hyperparameter recipe.

Official references: [agent initialization options](https://www.mathworks.com/help/reinforcement-learning/ref/rl.option.rlagentinitializationoptions.html) describes UseRNN and hidden width; [SAC algorithm](https://www.mathworks.com/help/reinforcement-learning/ug/soft-actor-critic-agents.html) distinguishes sequence batches from individual-transition batches. Online docs include later releases; implementation compatibility is checked against local R2024b, not assumed from latest docs.

New course experiments/sac_mlp_stage1_v1/curriculum.json contains only original Stage1. Same route MAT, wind, reward environment spatial_v2, isDone and advance conditions (including2000 minimum) remain. Stage budget is2000 and on_limit=pause. Success means this single-stage pilot only, not the full eight-stage course. The original curriculum and existing snapshots are unchanged. Fresh weights, replay and optimizer; there is no recovery.json parent. experiment_protocol.json records the independent experiment intent.

Preparation makes a serialCPU run, fastRestart off, checkpoint100,500 episodes/process, maxAttempts1 and maxNoProgressFailures1. Guard uses established100-window/patience3/0.5 ratios/min-reference500 and a total2000-episode cap. The first launch is at most500 episodes (up to1.5M environment steps); total reviewed pilot at most2000 (up to6M). These are episode/upper-step bounds, not an exact interaction budget or wall-time limit. Stop after the first attempt and review; do not set maxAttempts0. Automatic frozen evaluation and best-checkpoint rollback are not implemented.

## Remote commands

First ensure old experiments are paused and update with git pull --ff-only. Do not use retry(resume=oldRun) to create this experiment. In MATLAB, execute preparation once:

```matlab
cd('D:\daniel\ModularTraining');
clear functions;
info=trainingtools.prepare_sac_mlp_trial();
sacDir=string(info.sessionDir);
writelines(sacDir,fullfile(pwd,'artifacts','sac-mlp-stage1-run.txt'));
retry(resume=sacDir,maxAttempts=1,fastRestart='off');
```

The new run's first process constructs a new agent; resume here refers to the just-prepared empty run, not old learned weights. Only user executes remote training.

Monitor:

```matlab
cd('D:\daniel\ModularTraining');
sacDir=string(strtrim(fileread(fullfile(pwd,'artifacts','sac-mlp-stage1-run.txt'))));
training_status(sacDir,50);
```

PowerShell plot:

```powershell
cd D:\daniel\ModularTraining
$session=(Get-Content '.\artifacts\sac-mlp-stage1-run.txt' -Raw).Trim()
python .\tools\plot_training_rewards.py "$session" --watch 6 --view
```

MaxAttempts1 causes normal segment-end pause. STOP forcibly terminates an active attempt; do not use it for normal segment-end saving. After completion return stdout plus status/model/control/experiment_protocol, curriculum state/guard state and diagnostics/worker_attempts.csv. Keep original run and all checkpoints.

## Review schedule

At500,1000,1500,2000 (only after explicitly reviewed continuation), inspect reward/steps/termination trends and actual interactions/time, then frozen-evaluate saved policies with exploration off/on on the unchanged Stage1 scenario. Early low reward is not alone a failure verdict: the old recurrent learner needed roughly1000 episodes to improve. Conversely one high-reward period is not stability. Require sustained full-length behavior and retained route accuracy across multiple saved checkpoints before designing progression to harder tasks. Do not lower termination/gating standards to produce a pass. Keep run-level evidence separate from fixed-route generalization claims.
