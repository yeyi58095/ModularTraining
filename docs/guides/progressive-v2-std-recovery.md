# Stage 4 exploration-scale recovery (2026-10-17)

The lab's frozen Agent18000 on new Stage 4 seeds 701:712 completed 11/12
episodes at the original exploration scale (mean reward 2402.6204), versus
12/12 at half standard deviation (2647.8399). Seed 705 improved from 302 to
3000 steps. Earlier seeds 601:606 were 6/6 in both modes. These are diagnostic
samples, not a certified success rate or proof of the cause of PPO collapse.

## Bounded learning trial

Use parent `20261016_162607_recovery_tpf699ae87`, checkpoint 18000, and recipe
`configs/recovery_v2_18000_std_half.json`. The parent must be paused/stopped.
The new branch inherits spatial_v2 and the recorded Stage 4 position.
Actor LR stays 2.5e-5; critic LR, PPO clip/entropy settings and reward remain
unchanged. Hardware is inherited. Five 100-episode segments give at most
500 additional episodes, ending at 18500; the existing two-window 80%
reward-and-steps guard can stop earlier. Do not clear a guard to continue.

Preparation appends a nonlearnable factor 0.5 after softplus, keeping the
public std output name `sdev`. Both sampled training actions and PPO's
probability calculations therefore use the transformed actor distribution.
It is not external action noise or clipping. Mean-function parameters,
critic parameters and all learnable weights are preserved at preparation.
The underlying std branch remains learnable: this does not enforce an
absolute noise ceiling, and future std may increase again. Mean behavior
can also change as observations and learning change.

The child records `explorationStdScale` in model.json and the recipe in
recovery.json, and replaces only its snapshot's builder/validator plus the
new scaling helper. Existing parent snapshots and checkpoints are untouched.
Repeated scaling is rejected. The changed actor is saved once; subsequent
attempts load that checkpoint without multiplying by 0.5 again.

Reconstructing the actor and calling setActor does not establish preservation
of private optimizer state. Treat this as a recovery intervention with that
limitation, not a controlled proof that std alone explains training results.
The implementation test checks persistence, mean/std replay, source hashes,
child snapshot validation and a tiny synthetic CPU PPO update. It does not
validate GPU/multi-worker flight training or long-term convergence.

## Lab commands

With training paused, pull the update in PowerShell. In MATLAB:

```matlab
cd D:\daniel\ModularTraining
clear prepare_recovery_training retry
rehash
parentSession = fullfile(pwd,"experiments","progressive_v2","runs", ...
    "20261016_162607_recovery_tpf699ae87");
trial = prepare_recovery_training(parentSession, ...
    "configs/recovery_v2_18000_std_half.json");
info = retry(resume=trial.sessionDir);
training_status(info.sessionDir);
```

When this bounded trial stops, inspect its guard and evaluate saved checkpoints
18000/18100/latest with exploration enabled at the default evaluation scale 1:
the stored actor already includes factor 0.5. Passing explorationStdScale=0.5
would apply another reduction during evaluation and is not the intended test.
