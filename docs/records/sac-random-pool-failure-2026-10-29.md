# Remote first attempt: worker pool startup failure

User-provided terminal evidence; no independent remote connection.

- Run: D:/daniel/ModularTraining/experiments/sac_random_route_v1/runs/20261029_185919_tp424f6b90_db57_4eef_8c45_cdf6367cf580.
- R2024b, GTX1660 GPU build preflight passed; six process workers requested and required. First attempt paused after failure with no new checkpoint, zero completed episodes.
- pool_starting: Processes, job storage C:/Users/user/AppData/Roaming/MathWorks/MATLAB/local_cluster_jobs/R2024b; started19:00:13.
- pool_error: elapsed13.8380364s, parallel:cluster:PoolRunValidation; worker shut down unexpectedly with status1 during task execution.
- worker_attempts: ActualWorkers0, PoolReadyFalse, pool_start_failed, exit1, total83.2s (includes process startup/exit). Zero means no ready usable pool, not proof no worker process started.
- Prior stdout preserving jobs1/2 with crash dumps does not identify the current failed job or establish those dumps' timing.
- Not a learning regression, not proof GPU caused failure or RAM insufficient. Keep run/receipt and crash jobs; do not retry identical training or delete jobs before diagnosis.
- Follow-up attachment: storage exists, 66 files; latest listed files date2026-10-14 09:47, not this attempt. Job2 dump explicitly reports access violation at2026-10-14 09:47:06; stack includes Stateflow/Simulink libraries. c.Jobs lists Job1 failed and Job2 finished with task status-1073741819. These retained historical jobs do not explain the new status1 failure. Historical license-command warning also cannot establish today's cause.
- Next: user-run single-worker pool-only diagnostic with a fresh project-local JobStorageLocation and diary; no training, no saved profile changes, no deletion of retained jobs. If successful, test six workers separately. Fresh storage and interactive client differ from the failed training child process, so success is not proof of a training fix. No runtime/parameters changed.

Reference: https://www.mathworks.com/help/parallel-computing/resolve-error-client-lost-connection-to-worker.html
