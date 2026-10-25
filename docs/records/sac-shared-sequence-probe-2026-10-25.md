# SAC shared recurrent-sequence probe

## Decision

User authorized continued diagnosis and potential curriculum changes. Current frozen and stored-state evidence does not isolate curriculum or alpha as the cause. Next command compares network behavior on identical inputs before selecting a new recipe; existing curricula and runs are untouched. This is a bounded read-only inference diagnostic, not another simulation or training attempt.

`trainingtools.probe_sac_replay_pair` reads the current pair receipt and verifies parent1100 SHA. It reads baseline1600 and largerReplay1600 replay separately, taking the most recent completed episode delimited by two terminal markers within the latest10000 transitions. It retains at most the first256 transitions from each episode. Missing boundaries cause an explicit error, not an invented episode start. The known runs are serial; this routine is intended for this pair, not arbitrary parallel multi-worker buffers.

Five checkpoint agents (parent1100, baseline1400/1600, largerReplay1400/1600) consume exactly the same two stored sequences. Actor and critic recurrent states start at zero at each identified episode start, advance at every recorded transition, and are reset between sequences. First64 steps are retained as warm-up; post-warm-up summaries require more than64 steps. At most2560 actor steps and5120 critic evaluations, no pool or Simulink startup. Checkpoints load sequentially, though one full checkpoint still must fit RAM.

Each report retains per-step Gaussian actor mean/std outputs and twin-critic Q values for recorded actions, plus post-warm-up summaries. These Gaussian parameters are before the agent's sampling/action transformation and are not directly physical command standard deviations. Comparing Q uses historical actions under each critic's own recurrent state; it is not a new policy rollout. No TD/Bellman residual is reported: a valid recurrent SAC TD calculation would additionally require correctly aligned target state, next actions and entropy correction. Twin disagreement alone cannot establish critic accuracy. Two selected episode prefixes do not describe the full replay distribution or generalization.

Each read takes the existing supervisor exclusive lock and requires paused status; source MAT hash is checked before/after. Weights are checked before/after inference. Only in-memory function device/state changes occur. Saved outputs contain the exact at-most512 source transitions in shared-sequences.mat and five JSON reports, plus receipt. Preserve this small input MAT when sharing the package; it is not a model checkpoint.

## Validation and remote command

Local R2024b test uses the existing small learned synthetic fixture and synthetic80-step episodes, without new training or simulation. It exercises repeatable recurrent reset, positive finite Gaussian std, finite twin Q, unchanged weights, shared episode extraction, full five-report output and active-run rejection. Remote128-unit models and latency are not measured by this test.

With all three runs paused, PowerShell `git pull --ff-only`, then MATLAB:

```matlab
cd('D:\daniel\ModularTraining');
clear functions;
receipt=fullfile(pwd,'artifacts','sac-replay-pair-latest.json');
outDir=trainingtools.probe_sac_replay_pair(receipt);
zipFile=char(outDir+".zip");
zip(zipFile,{'*.json','shared-sequences.mat'},char(outDir));
fprintf('\nSend ZIP:\n%s\n',zipFile);
```

If an error occurs, preserve completed outputs and report the error; do not edit status or remove locks. No instruction to resume training accompanies this diagnostic.
