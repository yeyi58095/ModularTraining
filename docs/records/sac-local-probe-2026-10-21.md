# Bounded local SAC probe — 2026-10-21

Correction: subsequent real-flight stacks select the newer `rl.internal.train.OffPolicyTrainer`, which honors LearningFrequency in the parallel path too. Direct replay calls below exercise a legacy/low-level entry and **do not establish a frequency bug in the active/default parallel trainer**. The earlier attribution to the remote slowdown is withdrawn. Device-restoration observations remain valid.

User explicitly authorized local testing with limited RAM. No MATLAB process was listed before launch. Physical RAM was approximately 31.7 GiB with 4.5 GiB available. Used one R2024b MATLAB process, no worker pool, no Simulink, no remote checkpoint/run, and no production runtime edits. Local GPU: RTX4070 Laptop, 8188 MiB (remote is GTX1660).

## Reproduction and scope

`tests/test_sac_learning_frequency_probe.m`: synthetic 10-observation/1-action environment, LSTM16, batch4, sequence4, replay128, warmup8. Each CPU/GPU and frequency1/8 case executes one 32-step serial episode followed by 32 direct calls to `learnFromExperiencesInMemory`, the entry used by ExpSyncParallelTrainer. Direct replay uses the already populated buffer; it is an isolated call-path probe, not an actual parallel training run or equal-start learning comparison.

Run from project root in a fresh process:

```powershell
& 'C:/Program Files/MATLAB/R2024b/bin/matlab.exe' -batch "addpath('tests'); test_sac_learning_frequency_probe" -logfile tests/output/sac-frequency-probe.log
```

Final execution exit=0. Assertions verify serial frequency reduces learning calls, direct replay makes 32 calls for both frequency values, direct replay changes actor weights, and small MAT save/load preserves actor/critic learnable weights and replay length. The profiler counts `rlSACAgent.learnFromBatchData_`, not every individual optimizer operation.

## Results

| Device | Frequency | Serial batch-learning calls (32 steps) | Direct replay calls (32 invocations) |
| --- | ---: | ---: | ---: |
| CPU | 1 | 25 | 32 |
| CPU | 8 | 4 | 32 |
| GPU | 1 | 25 | 32 |
| GPU | 8 | 4 | 32 |

Serial frequency1 has 25 calls because learning starts at warmup8. The frequency gate works in serial; the direct entry bypasses it. This characterizes the direct entry, not the active/default parallel trainer. This is not a measured 32x speedup, full six-worker validation, or convergence evidence.

### GPU device restoration finding

Both GPU cases asserted actor and both critics were GPU immediately after construction. After actual GPU training, saving and loading the small agent MAT produced actor=cpu and both critics=cpu. Both CPU cases remained cpu. Actor/critic weights (gathered for comparison) and replay length were retained in all four cases. Optimizer/target private-state equivalence was not tested.

R2024b `rlContinuousGaussianActor.loadobj` and `rlQValueFunction.loadobj` reconstruct objects without explicitly restoring UseDevice. The project resume path loads saved agents without reapplying or validating the configured device. This is a reproduced local mechanism compatible with low remote GPU use and slower resumed attempts, not direct inspection of the remote in-memory agent.

Timings with profiler on: CPU serial f1/f8 5.72/2.69s, direct replay 2.10/2.62s; GPU serial 7.98/4.71s, direct replay 6.35/6.47s. Small batches, sequential warmup effects, different serial vs direct initial replay and profiler overhead make these unsuitable for production CPU/GPU recommendations. Restoring GPU does not guarantee faster training.

## Test development and artifacts

Initial sandbox launch could not write MATLAB preferences; approved escalated execution enabled normal MATLAB initialization. First test run stopped on a test-only enum comparison error; comparison was corrected to string. Second run intentionally exposed the device-preservation assertion failure for GPU. The final test records actual device behavior rather than assuming it is preserved, and retains independent weight/replay assertions.

Artifacts are local ignored `tests/output/sac-frequency-probe/report.json`, four small MATs and `tests/output/sac-frequency-probe.log`. No full logs/models were added to Git. Production code and remote training were not changed.

## Next boundary

Before subsequent resumed production training, implement and test an explicit device-restoration policy that also verifies optimizer/target preservation, and an execution-mode choice that honors intended SAC learning frequency. Existing active run/checkpoint snapshots remain unchanged. Any different execution/sampling policy requires a separate branch/run with lineage and bounded evaluation; neither this probe nor GPU restoration proves reward-regression repair.
