# SAC execution-path review — 2026-10-21

## Correction after real-flight execution (authoritative)

The initial frequency-bypass inference below is **withdrawn for the active/default trainer**. The actual R2024b flight stack uses `rl.internal.train.OffPolicyTrainer`, selected by `rl.util.rlfeature("TrainerVersion") > 1` in `+rl/+agent/@AbstractAgent/train.m`. This newer trainer reads LearningFrequency (line72) and computes outer epochs from received experiences divided by that frequency (lines164–169), including its parallel path. ExpSyncParallelTrainer is a legacy path, not evidence of the selected trainer. Remote trainer selection has not been independently queried.

The direct-replay test demonstrates the explicit low-level/legacy entry only; it does not prove the remote six-worker run bypassed LearningFrequency, or that serial execution fixes a frequency bug. Serial CPU is an explicitly chosen low-memory comparison recipe. The independently reproduced GPU-to-CPU save/load issue remains valid, as does preserving entropy PolicyState. Do not cite legacy call counts as the explanation of the remote slowdown.

## Initial audit retained for provenance (legacy-path scope only)

Read-only review requested while remote attempt3 is active. No runtime changes, MATLAB execution, training, process termination or remote connection. Source evidence is project code plus locally installed MATLAB R2024b readable toolbox source. Remote toolbox update/patch level is not independently verified.

## Execution model and main finding

The project sets UseParallel=true and ParallelizationOptions.Mode="sync" in runtime/training_engine.m (398–403). R2024b createTrainer.m selects ExpSyncParallelTrainer for InternalMemoryTrainable agents, including SAC. SyncParallelTrainer.processFutures_ fetches outputs and synchronously calls processSimOutputs_. ExpSyncParallelTrainer.processSimOutputs_ iterates over each returned episode, appends its experiences, then calls learnFromExperiencesInMemory once per experience. This creates a substantial main-process learning phase between simulation batches.

Critically, this path does not call AbstractOffPolicyAgent.learnFromExperiencesInMemoryAtFrequency_, which is the gate that applies LearningFrequency. The ordinary SAC learn_ path calls that gate with AgentOptions.LearningFrequency; the parallel path calls the memory-learning method directly. rlSACAgent.learnFromExperiencesInMemory_ checks warm-start/batch readiness, samples a batch with SequenceLength, then invokes learnFromBatchData. It does not apply LearningFrequency=32 there.

Therefore the configuration value 32 is not sufficient evidence of one replay-learning call per 32 transitions in this parallel path. After warm-up, 3000 returned transitions can cause 3000 replay-learning calls, rather than roughly 94 under a frequency-32 gate. Six complete 3000-step episodes can cause 18000 calls before moving on. This is a call-count comparison, not a measured 32x runtime slowdown or proof every invocation performed an optimizer update. MiniBatchSize=64, SequenceLength=32, twin critics and recurrent state processing add work to these calls. MaxMiniBatchPerEpoch=1 does not cap the outer per-experience loop.

This gives a concrete explanation compatible with the user's busy main PID22304 and idle pool children. It does not by itself explain low GPU utilization or establish the cause of reward collapses. ExpAsyncParallelTrainer also calls learnFromExperiencesInMemory directly inside a learning loop; switching to async is not a demonstrated fix for the frequency discrepancy.

## GPU, startup, storage and logging

- build_sac.m explicitly assigns UseDevice to actor and both critics for a new agent. Resume loads the saved agent directly in training_engine.m:263; it does not reapply trainingDevice. validate_sac.m verifies architecture/options but not actual actor/critic UseDevice. Thus config gpu is not an audit of resumed device state. No evidence here proves device state was lost.
- checkpoint_select_agent loads an entire candidate agent to validate it, discards it, then training_engine loads it again. Several paths also reread history. With saved replay/optimizer/targets this is avoidable startup work worth measuring, consistent with but not proven responsible for the roughly six-minute pre-pool interval in attempts2/3.
- Every 100 episodes the framework saves a v7.3 checkpoint; replay/optimizer/target saving is enabled. Every attempt also saves Agent_Initial; final save publishes Agent_Final then copies it to the run log directory. Serialization and disk work are plausible intermittent costs, not measured explanations for the entire attempt.
- TransferBaseWorkspaceVariables is on; base workspace contains the resumed agent/history and other script data. Transfer size has not been measured.
- DataQueue wind logging occurs once per reset, memory logging once per 100 worker episodes. These custom callbacks do not write a row for every simulation step. progress_callback runs per episode and evaluates a few bounded recent windows (with history arrays copied); no evidence that this small custom logger dominates runtime.
- TrainingPlots is explicitly none in checkpoint_attempt, SimulationStorageType is none, and FastRestart defaults on. Do not recommend toggling already-disabled training plots as a fix.

## Evidence boundaries

Remote attempt3 environment_used.json reports engine SHA AF2CB573B227677058D52B9E7DF74C075E7BC5D2E02D7F602F735B66E370B990. Local engine LF SHA is B3AE4B550670D1E7FA07E97622497B752F62B7CC1E3BB8D6CC3D2EBF81D69028; converting only LF to CRLF produces the exact reported remote SHA. This binds the reviewed engine content, not all toolbox/model-source files.

Local toolbox source paths relative to C:/Program Files/MATLAB/R2024b/toolbox/rl/rl:

- +rl/+train/createTrainer.m:20–30
- +rl/+train/+parallel/SyncParallelTrainer.m: processFutures_
- +rl/+train/+parallel/ExpSyncParallelTrainer.m: processSimOutputs_; SHA256 30DADCB100DD4258FD4F6C7760820D332925983AC383EA1CC42AB06B7AC22056
- +rl/+agent/rlSACAgent.m:238,382–445; SHA256 9AC2F3DCDE3EB8C1D640C11CC77F825381EEEC74C19918845F3EA5DA9EE4CC47
- +rl/+agent/AbstractOffPolicyAgent.m:78 frequency gate

[MathWorks R2024b parallel/GPU documentation](https://www.mathworks.com/help/releases/R2024b/reinforcement-learning/ug/train-agents-using-parallel-computing-and-gpu.html) describes workers producing experiences, client learning, synchronous waiting, and GPU transfer overhead. It also explicitly states recurrent-agent parallel training/simulation is unsupported. Local readable source and received logs demonstrate an executable path but do not establish supported recurrent parallel semantics. This discrepancy must remain visible; neither an immediate failure nor correctness can be inferred from the documentation note alone.

## Next implementation direction

Keep current run intact and honor the requested graceful pause. Before another training run, verify remote toolbox file hashes and saved actor/critic device properties. Use a separate bounded diagnostic to count learning calls and gradient steps, measure simulation/replay preparation/learning/save durations, and compare an explicitly configured serial SAC path that honors the frequency gate. Serial here means no worker pool; GPU choice is independent. Any comparison changes execution/sampling semantics and requires a separate run/lineage and matched evaluation, not rewriting existing snapshots. Do not patch MathWorks installation files, silently change LR or batch size, remove replay saving, or claim convergence/32x speedup.
