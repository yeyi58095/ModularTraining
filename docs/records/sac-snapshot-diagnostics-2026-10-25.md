# Read-only SAC checkpoint diagnostics

Following the frozen pair review, added `trainingtools.inspect_sac_checkpoint` and `trainingtools.inspect_sac_replay_pair`. R2024b source inspection confirms getEntropyWeight returns the current coefficient and saveobj conditionally retains PolicyState. This audit uses loaded saved state without setting options, reconstructing agents, changing devices, training, or simulation.

The pair entry checks the receipt parent SHA and paused status, then sequentially audits parent1100, baseline1400/1600 and largerReplay1400/1600. Each checkpoint obtains the existing supervisor lock exclusively, verifies paused status again, and hashes the MAT before and after. No source files are saved or snapshots rewritten. Output is a unique artifacts folder containing five reports and a receipt copy, with each report written as it completes.

Reports include current entropy coefficient and saved-state presence, configured learning rates/sequence/batch/frequency, finite parameter norms and nonfinite counts for actor/twin critics/targets, critic-target parameter gaps, optimizer-presence flags and bounded recent replay reward/terminal statistics. Only the most recent at most10000 transitions are inspected, not the full500k buffer. Loaded MAT memory is still required; sequential processing avoids holding five agents simultaneously. Full-file hashing adds I/O time.

Limits: no historical losses, update counts, full replay composition, Q-calibration or policy action-distribution evaluation. Optimizer presence is not proof of healthy optimization or exact training history. A large parameter norm/gap is not by itself a failure diagnosis. If policy state was not saved, the loaded entropy coefficient cannot be asserted to be its historical value. The five states distinguish candidate mechanisms but cannot prove a learning-rate/entropy cause. Source hash guarantees unchanged files, not a new generalization test.

Validation uses an existing small synthetic SAC fixture, without training/simulation. Checks entropy value, retained replay length/capacity, finite network summaries, JSON encoding, source hash, active-run rejection and complete five-report wrapper output. No remote-sized checkpoint or remote execution tested locally.

Remote: keep all runs paused, `git pull --ff-only`, then in MATLAB:

```matlab
cd('D:\daniel\ModularTraining');
outDir=trainingtools.inspect_sac_replay_pair( ...
    fullfile(pwd,'artifacts','sac-replay-pair-latest.json'));
zipFile=char(outDir+".zip");
zip(zipFile,'*.json',char(outDir));
fprintf('\nSend this ZIP:\n%s\n',zipFile);
```

This is a diagnostic command, not authorization to resume training. On failure, preserve completed JSON reports and share the exact error; do not delete locks or edit status to bypass checks.
